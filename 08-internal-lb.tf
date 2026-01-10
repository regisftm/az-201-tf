##############################################################################################################
#
#  INTERNAL LOAD BALANCER
#  ======================
#
#  The Internal Load Balancer (ILB) handles traffic FROM protected resources TO the internet/VNet.
#  It distributes outbound traffic across all FortiGate VMs for load balancing and HA.
#
#  KEY DIFFERENCE FROM EXTERNAL LB:
#  --------------------------------
#  - External LB: Internet -> FortiGate (inbound)
#  - Internal LB: Protected Resources -> FortiGate -> Internet (outbound)
#
#  INTERNAL LOAD BALANCER FLOW:
#  ----------------------------
#
#  [Protected VM: 10.100.3.10]
#       |
#       | (wants to reach internet)
#       |
#       v
#  [Route Table: next_hop = ILB IP]
#       |
#       v
#  +---------------------------+
#  | Internal Load Balancer    |  <-- Private IP in Internal subnet
#  | - HA Ports Rule           |      Routes ALL traffic (any port/protocol)
#  | - Health Probes           |      Monitors FortiGate health
#  +---------------------------+
#       |
#       v (distributed across healthy FortiGates)
#  +---------------------------+
#  | FortiGate-0 or -1 or -N   |  <-- Inspects, applies policy, NATs
#  +---------------------------+
#       |
#       v
#  [Internet / Other VNets]
#
##############################################################################################################


##############################################################################################################
# INTERNAL LOAD BALANCER
# ----------------------
# Unlike the External LB, the Internal LB uses a private IP address.
# This IP becomes the "gateway" for the protected subnet via the route table.
##############################################################################################################

resource "azurerm_lb" "ilb" {
  # name: Name of the Internal Load Balancer
  name                = "${var.prefix}-internalloadbalancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.resourcegroup.name
  
  # sku: Must be Standard to use HA Ports feature
  # Standard SKU is required for routing all traffic (any port/protocol)
  sku                 = "Standard"

  # frontend_ip_configuration: Internal LB uses a private IP
  frontend_ip_configuration {
    # name: Identifier for this frontend
    name                          = "${var.prefix}-ilb-pip"
    
    # subnet_id: The subnet where the private IP will be allocated
    # Using the Internal subnet (where FortiGate internal NICs are)
    subnet_id                     = azurerm_subnet.subnet2.id
    
    # private_ip_address_allocation: How the private IP is assigned
    # - Dynamic: Azure assigns an available IP from the subnet
    # - Static: You specify the exact IP address
    # Dynamic is simpler; Static is useful when you need a predictable IP
    private_ip_address_allocation = "Dynamic"
  }
}


##############################################################################################################
# BACKEND ADDRESS POOL
# --------------------
# The backend pool for the Internal LB contains FortiGate internal interfaces.
# Traffic sent to the ILB frontend is distributed to NICs in this pool.
##############################################################################################################

resource "azurerm_lb_backend_address_pool" "ilbbackend" {
  # loadbalancer_id: The Internal Load Balancer this pool belongs to
  loadbalancer_id = azurerm_lb.ilb.id
  
  # name: Identifier for this backend pool
  name            = "backend-pool-internal"
}


##############################################################################################################
# HEALTH PROBE
# ------------
# Same concept as External LB - checks if FortiGates are healthy.
# Uses the same probe port (8008) configured on FortiGate.
##############################################################################################################

resource "azurerm_lb_probe" "ilbprobe" {
  loadbalancer_id     = azurerm_lb.ilb.id
  name                = "lbprobe"
  
  # port: FortiGate probe-response port
  port                = 8008
  
  # interval_in_seconds: Probe frequency
  interval_in_seconds = 5
  
  # number_of_probes: Failures before marking unhealthy
  number_of_probes    = 2
  
  # protocol: TCP probe
  protocol            = "Tcp"
}


##############################################################################################################
# HA PORTS RULE
# -------------
# THIS IS THE KEY FEATURE OF THE INTERNAL LOAD BALANCER!
#
# HA Ports (High Availability Ports) allow load balancing of ALL traffic:
# - Any protocol (TCP, UDP, ICMP, etc.)
# - Any port (0-65535)
#
# This is essential because:
# - Protected VMs might use any protocol/port to reach the internet
# - Without HA Ports, you'd need a separate LB rule for each port
# - HA Ports provides a "catch-all" rule for all traffic
#
# HA PORTS REQUIREMENTS:
# - Standard SKU Load Balancer
# - Internal Load Balancer only (not External)
# - frontend_port = 0, backend_port = 0, protocol = "All"
##############################################################################################################

resource "azurerm_lb_rule" "lb_haports_rule" {
  # loadbalancer_id: The Internal Load Balancer
  loadbalancer_id                = azurerm_lb.ilb.id
  
  # name: Name of this HA Ports rule
  name                           = "lb_haports_rule"
  
  # protocol: "All" means TCP, UDP, and ICMP
  # This is required for HA Ports
  protocol                       = "All"
  
  # frontend_port: 0 means "all ports"
  # This is the HA Ports magic - handles any port
  frontend_port                  = 0
  
  # backend_port: 0 means "same as frontend port"
  # Port translation is not available with HA Ports
  backend_port                   = 0
  
  # frontend_ip_configuration_name: The ILB frontend
  frontend_ip_configuration_name = "${var.prefix}-ilb-pip"
  
  # probe_id: Health probe for FortiGate status
  probe_id                       = azurerm_lb_probe.ilbprobe.id
  
  # backend_address_pool_ids: FortiGate internal NICs
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ilbbackend.id]
}


##############################################################################################################
# INTERNAL LOAD BALANCER NOTES
# ----------------------------
#
# WHY INTERNAL LB IS NEEDED:
# Azure's default routing sends traffic directly between subnets.
# To force traffic through FortiGate, we need:
# 1. Route table pointing to ILB's private IP
# 2. ILB distributing traffic to FortiGate internal interfaces
# 3. FortiGate inspecting and forwarding traffic
#
# TRAFFIC FLOW EXAMPLE:
# 1. Protected VM (10.100.3.10) wants to reach 8.8.8.8
# 2. Route table says: 0.0.0.0/0 -> ILB private IP
# 3. ILB receives traffic, health checks FortiGates
# 4. ILB forwards to healthy FortiGate (e.g., 10.100.2.4)
# 5. FortiGate inspects traffic, applies policies
# 6. FortiGate forwards to internet via external interface
# 7. Return traffic follows same path (stateful)
#
# SESSION PERSISTENCE:
# Standard LB uses 5-tuple hash for session persistence:
# - Same (src IP, src port, dst IP, dst port, protocol) -> same FortiGate
# - Ensures stateful firewall sessions stay on same FortiGate
#
# HA PORTS LIMITATIONS:
# - Only available on Internal Load Balancer
# - Requires Standard SKU
# - Cannot use with NAT rules (NAT rules need specific ports)
# - Cannot do port translation (frontend port must equal backend port)
#
# ACCESSING ILB IP IN OTHER RESOURCES:
# azurerm_lb.ilb.private_ip_address
# This is used in the route table as the next_hop_in_ip_address
#
##############################################################################################################