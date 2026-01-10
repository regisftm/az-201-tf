##############################################################################################################
#
#  EXTERNAL LOAD BALANCER
#  ======================
#
#  The External Load Balancer (ELB) distributes incoming internet traffic across FortiGate VMs.
#  It provides a single public IP address as the entry point for all inbound services.
#
#  EXTERNAL LOAD BALANCER COMPONENTS:
#  ----------------------------------
#
#  [Internet]
#       |
#       v
#  +------------------+
#  | Public IP        |  <-- Single entry point
#  | (ELB Frontend)   |
#  +------------------+
#       |
#       v
#  +------------------+
#  | Load Balancer    |  <-- Distributes traffic
#  | - Health Probes  |      Monitors FortiGate health
#  | - LB Rules       |      Defines port mappings
#  | - NAT Rules      |      Management access (SSH/HTTPS)
#  +------------------+
#       |
#       v
#  +------------------+
#  | Backend Pool     |  <-- FortiGate NICs
#  | - FortiGate-0    |
#  | - FortiGate-1    |
#  | - FortiGate-N    |
#  +------------------+
#
##############################################################################################################


##############################################################################################################
# PUBLIC IP ADDRESS FOR EXTERNAL LOAD BALANCER
# --------------------------------------------
# This Public IP is the single point of entry from the internet.
# All inbound traffic to FortiGate arrives through this IP.
##############################################################################################################

resource "azurerm_public_ip" "elbpip" {
  # name: Descriptive name for the Public IP
  name                = "${var.prefix}-elb-pip"
  
  # location: Must be in the same region as the Load Balancer
  location            = var.location
  
  # resource_group_name: The Resource Group for this resource
  resource_group_name = azurerm_resource_group.resourcegroup.name
  
  # allocation_method: How the IP address is assigned
  # - Static: IP address is reserved and doesn't change
  # - Dynamic: IP assigned when resource starts (can change on restart)
  # Standard SKU Load Balancers require Static allocation
  allocation_method   = "Static"
  
  # sku: The SKU (tier) of the Public IP
  # - Basic: Lower cost, no availability zones, limited features
  # - Standard: Zone-redundant, required for Standard LB, more features
  # Must match the Load Balancer SKU
  sku                 = "Standard"
  
  # domain_name_label: Creates a DNS name for easier access
  # Full FQDN will be: <label>.<region>.cloudapp.azure.com
  # Example: rw-az201-lb-pip.canadacentral.cloudapp.azure.com
  domain_name_label   = format("%s-%s", lower(var.prefix), "lb-pip")
}


##############################################################################################################
# EXTERNAL LOAD BALANCER
# ----------------------
# The Azure Load Balancer distributes incoming traffic across backend VMs.
# Standard SKU provides: zone redundancy, multiple frontend IPs, HA ports, and more.
##############################################################################################################

resource "azurerm_lb" "elb" {
  # name: Name of the Load Balancer
  name                = "${var.prefix}-externalloadbalancer"
  location            = var.location
  resource_group_name = azurerm_resource_group.resourcegroup.name
  
  # sku: Standard or Basic
  # Standard is required for:
  # - Availability zones
  # - HA ports (internal LB)
  # - Multiple backend pools
  # - More than 300 instances
  sku                 = "Standard"

  # frontend_ip_configuration: Where traffic enters the Load Balancer
  # External LB uses a Public IP; Internal LB uses a private IP
  frontend_ip_configuration {
    # name: Identifier for this frontend (referenced in rules)
    name                 = "${var.prefix}-elb-pip"
    
    # public_ip_address_id: Associates the Public IP with this frontend
    # Traffic to the Public IP will be handled by this Load Balancer
    public_ip_address_id = azurerm_public_ip.elbpip.id
  }
}


##############################################################################################################
# BACKEND ADDRESS POOL
# --------------------
# The backend pool is a collection of VMs (FortiGates) that receive traffic.
# NICs are added to this pool in 09-fortigate-nics.tf.
##############################################################################################################

resource "azurerm_lb_backend_address_pool" "elbbackend" {
  # loadbalancer_id: The Load Balancer this pool belongs to
  loadbalancer_id = azurerm_lb.elb.id
  
  # name: Identifier for this backend pool
  name            = "backend-pool-external"
}


##############################################################################################################
# HEALTH PROBE
# ------------
# Health probes check if backend VMs are healthy and ready to receive traffic.
# Unhealthy VMs are automatically removed from the rotation.
#
# FORTIGATE PROBE RESPONSE:
# FortiGate is configured (in customdata.tpl) to respond to HTTP probes on port 8008.
# This is a dedicated probe port that doesn't conflict with production traffic.
##############################################################################################################

resource "azurerm_lb_probe" "elbprobe" {
  # loadbalancer_id: The Load Balancer this probe belongs to
  loadbalancer_id     = azurerm_lb.elb.id
  
  # name: Identifier for this probe
  name                = "lbprobe"
  
  # port: The port to check
  # Port 8008 is configured on FortiGate as the probe-response port
  port                = 8008
  
  # interval_in_seconds: How often to probe (in seconds)
  # Lower = faster failover, but more probe traffic
  interval_in_seconds = 5
  
  # number_of_probes: Failed probes before marking unhealthy
  # With interval=5 and number_of_probes=2, failover takes ~10 seconds
  number_of_probes    = 2
  
  # protocol: TCP or HTTP/HTTPS
  # TCP just checks if the port is open
  # HTTP checks for specific response (more reliable)
  protocol            = "Tcp"
}


##############################################################################################################
# LOAD BALANCER RULE: HTTP (TCP/80)
# ---------------------------------
# This rule distributes HTTP traffic to all FortiGates in the backend pool.
# Use case: Web server behind FortiGate, incoming HTTP traffic.
##############################################################################################################

resource "azurerm_lb_rule" "lbruletcp" {
  # loadbalancer_id: The Load Balancer this rule belongs to
  loadbalancer_id                = azurerm_lb.elb.id
  
  # name: Descriptive name for this rule
  name                           = "public-lb-rule-fe1-http-80"
  
  # protocol: TCP, UDP, or All
  protocol                       = "Tcp"
  
  # frontend_port: Port on the Load Balancer (public-facing)
  frontend_port                  = 80
  
  # backend_port: Port on the FortiGate VMs
  # Can be different from frontend_port (port translation)
  backend_port                   = 80
  
  # frontend_ip_configuration_name: Which frontend to use
  # Must match the name defined in the Load Balancer
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
  
  # probe_id: Health probe to use for this rule
  # Only healthy FortiGates receive traffic
  probe_id                       = azurerm_lb_probe.elbprobe.id
  
  # backend_address_pool_ids: Which backend pool(s) to distribute to
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.elbbackend.id]

  floating_ip_enabled            = true
}


##############################################################################################################
# LOAD BALANCER RULE: UDP/10551
# -----------------------------
# This rule distributes UDP traffic on port 10551 to FortiGates.
# Use case: Custom UDP application, VPN, or logging traffic.
##############################################################################################################

resource "azurerm_lb_rule" "lbruleudp" {
  loadbalancer_id                = azurerm_lb.elb.id
  name                           = "public-lb-rule-fe1-udp-10551"
  
  # protocol: UDP for this rule
  protocol                       = "Udp"
  
  # Port 10551 on both frontend and backend
  frontend_port                  = 10551
  backend_port                   = 10551
  
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
  probe_id                       = azurerm_lb_probe.elbprobe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.elbbackend.id]

  floating_ip_enabled            = true
}

##############################################################################################################
# LOAD BALANCER RULE: TCP/2222
# -----------------------------
# This rule distributes TCP traffic on port 2222 to FortiGates.
# Use case: To allow access to servers behind the FortiGate using VIPs
##############################################################################################################

resource "azurerm_lb_rule" "lbruletcp2222" {
  loadbalancer_id                = azurerm_lb.elb.id
  name                           = "public-lb-rule-fe1-tcp-2222"
  
  # protocol: TCP for this rule
  protocol                       = "Tcp"
  
  # Port 2222 on both frontend and backend
  frontend_port                  = 2222
  backend_port                   = 2222
  
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
  probe_id                       = azurerm_lb_probe.elbprobe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.elbbackend.id]

  disable_outbound_snat          = true
}


##############################################################################################################
# LOAD BALANCER RULE: TCP/8080
# -----------------------------
# This rule distributes TCP traffic on port 8080 to FortiGates.
# Use case: To allow access to the app-server application behind the FortiGate using VIPs
##############################################################################################################

resource "azurerm_lb_rule" "lbruletcp8080" {
  loadbalancer_id                = azurerm_lb.elb.id
  name                           = "public-lb-rule-fe1-tcp-8080"
  
  # protocol: TCP for this rule
  protocol                       = "Tcp"
  
  # Port 8080 on both frontend and backend
  frontend_port                  = 8080
  backend_port                   = 8080
  
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
  probe_id                       = azurerm_lb_probe.elbprobe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.elbbackend.id]

  disable_outbound_snat          = true
}


##############################################################################################################
# NAT RULES FOR FORTIGATE MANAGEMENT - HTTPS
# ------------------------------------------
# NAT rules provide direct access to individual FortiGates for management.
# Each FortiGate gets a unique port mapping:
#   - FortiGate-0: Public IP:40030 -> FortiGate-0:443
#   - FortiGate-1: Public IP:40031 -> FortiGate-1:443
#   - FortiGate-N: Public IP:4003N -> FortiGate-N:443
#
# This allows administrators to access each FortiGate's GUI individually.
##############################################################################################################

resource "azurerm_lb_nat_rule" "fgtmgmthttps" {
  # count: Create one NAT rule per FortiGate
  # Using count creates multiple instances of this resource
  count                          = var.fgt_count
  
  # resource_group_name: Required for NAT rules
  resource_group_name            = azurerm_resource_group.resourcegroup.name
  
  # loadbalancer_id: The Load Balancer this NAT rule belongs to
  loadbalancer_id                = azurerm_lb.elb.id
  
  # name: Unique name for each NAT rule
  # count.index is 0, 1, 2... for each instance
  name                           = "${var.prefix}-fgt-${count.index}-https"
  
  # protocol: TCP for HTTPS management
  protocol                       = "Tcp"
  
  # frontend_port: Unique port for each FortiGate
  # 40030 + 0 = 40030 (FortiGate-0)
  # 40030 + 1 = 40031 (FortiGate-1)
  frontend_port                  = 40030 + count.index  # 40030, 40031, 40032...
  
  # backend_port: Standard HTTPS port on FortiGate
  backend_port                   = 443
  
  # frontend_ip_configuration_name: Which frontend IP to use
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
}


##############################################################################################################
# NAT RULES FOR FORTIGATE MANAGEMENT - SSH
# ----------------------------------------
# Similar to HTTPS NAT rules, but for SSH access:
#   - FortiGate-0: Public IP:50030 -> FortiGate-0:22
#   - FortiGate-1: Public IP:50031 -> FortiGate-1:22
#   - FortiGate-N: Public IP:5003N -> FortiGate-N:22
#
# This allows administrators to SSH to each FortiGate for CLI management.
##############################################################################################################

resource "azurerm_lb_nat_rule" "fgtmgmtssh" {
  count                          = var.fgt_count
  resource_group_name            = azurerm_resource_group.resourcegroup.name
  loadbalancer_id                = azurerm_lb.elb.id
  
  # name: Unique name for each SSH NAT rule
  name                           = "${var.prefix}-fgt-${count.index}-ssh"
  protocol                       = "Tcp"
  
  # frontend_port: Starting at 50030 for SSH
  frontend_port                  = 50030 + count.index  # 50030, 50031, 50032...
  
  # backend_port: Standard SSH port
  backend_port                   = 22
  
  frontend_ip_configuration_name = "${var.prefix}-elb-pip"
}


##############################################################################################################
# DATA SOURCE: PUBLIC IP (FOR OUTPUT)
# -----------------------------------
# This data source reads the Public IP after it's allocated.
# Used to display the IP address in the deployment output.
##############################################################################################################

data "azurerm_public_ip" "elbpip" {
  # name: The name of the Public IP to read
  name                = azurerm_public_ip.elbpip.name
  
  # resource_group_name: Where the Public IP is located
  resource_group_name = azurerm_resource_group.resourcegroup.name
  
  # depends_on: Ensures the Load Balancer is created first
  # The Public IP might not have an IP address until it's attached to something
  depends_on          = [azurerm_lb.elb]
}


##############################################################################################################
# EXTERNAL LOAD BALANCER NOTES
# ----------------------------
#
# LOAD BALANCING ALGORITHMS:
# Standard LB uses a 5-tuple hash by default:
# - Source IP, Source Port, Destination IP, Destination Port, Protocol
# This ensures session persistence (same client -> same backend)
#
# HEALTH PROBE BEHAVIOR:
# - Healthy: Backend responds correctly to probe
# - Unhealthy: No response or wrong response after N failures
# - Only healthy backends receive traffic
# - Traffic redistributes automatically during failover
#
# NAT RULE vs LB RULE:
# - LB Rule: Distributes traffic across all healthy backends
# - NAT Rule: Sends traffic to ONE specific backend (1:1 mapping)
#
# IMPORTANT PORTS:
# - 40030+: FortiGate HTTPS management
# - 50030+: FortiGate SSH management
# - 80: HTTP load balanced traffic
# - 10551: UDP load balanced traffic
# - 8008: Health probe (not exposed externally)
#
##############################################################################################################