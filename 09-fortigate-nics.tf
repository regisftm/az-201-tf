##############################################################################################################
#
#  FORTIGATE NETWORK INTERFACES (NICs)
#  ====================================
#
#  Each FortiGate VM requires two network interfaces:
#  - NIC1 (port1): External interface - connects to internet via External LB
#  - NIC2 (port2): Internal interface - connects to protected networks via Internal LB
#
#  NETWORK INTERFACE ARCHITECTURE:
#  -------------------------------
#
#  +-------------------+          +-------------------+
#  |   FortiGate-0     |          |   FortiGate-1     |
#  |                   |          |                   |
#  | [NIC1/port1]      |          | [NIC1/port1]      |  <-- External subnet
#  |   10.100.1.x      |          |   10.100.1.y      |      (Dynamic IP)
#  |                   |          |                   |
#  | [NIC2/port2]      |          | [NIC2/port2]      |  <-- Internal subnet
#  |   10.100.2.x      |          |   10.100.2.y      |      (Dynamic IP)
#  +-------------------+          +-------------------+
#          |                              |
#          +------------------------------+
#                        |
#                        v
#            Associated with NSG, LB Backend Pools, NAT Rules
#
##############################################################################################################


##############################################################################################################
# EXTERNAL NETWORK INTERFACE (NIC1 / port1)
# -----------------------------------------
# This NIC connects FortiGate to the External subnet for internet-facing traffic.
# It's associated with:
# - Network Security Group (NSG)
# - External Load Balancer backend pool
# - NAT rules for management access (SSH, HTTPS)
##############################################################################################################

resource "azurerm_network_interface" "fgtifc1" {
  # count: Create one NIC per FortiGate VM
  # count.index will be 0, 1, 2... for each FortiGate
  count                          = var.fgt_count
  
  # name: Unique name for each NIC
  # Example: rw-az201-fgt-0-nic1, rw-az201-fgt-1-nic1
  name                           = "${var.prefix}-fgt-${count.index}-nic1"
  
  # location: Must be in the same region as the VM
  location                       = azurerm_resource_group.resourcegroup.location
  
  # resource_group_name: The Resource Group for this NIC
  resource_group_name            = azurerm_resource_group.resourcegroup.name
  
  # ip_forwarding_enabled: CRITICAL for FortiGate!
  # Allows the NIC to forward traffic not destined for its own IP
  # Without this, FortiGate cannot act as a router/firewall
  # Azure calls this "IP forwarding" or "enable forwarding"
  ip_forwarding_enabled          = true

  # accelerated_networking_enabled: Optional performance feature
  # Bypasses the host's virtual switch for lower latency
  # Requires compatible VM size (most F-series and D-series)
  accelerated_networking_enabled = var.fgt_accelerated_networking

  # ip_configuration: The IP settings for this NIC
  ip_configuration {
    # name: Identifier for this IP configuration
    # A NIC can have multiple IP configurations (for multiple IPs)
    name                          = "interface1"
    
    # subnet_id: Which subnet this NIC belongs to
    # Using subnet1 (External subnet: 10.100.1.0/24)
    subnet_id                     = azurerm_subnet.subnet1.id
    
    # private_ip_address_allocation: How the private IP is assigned
    # - Dynamic: Azure assigns an available IP from the subnet
    # - Static: You specify the exact IP (use private_ip_address = "x.x.x.x")
    # Dynamic is simpler for this deployment
    private_ip_address_allocation = "Dynamic"
  }
}


##############################################################################################################
# NSG ASSOCIATION FOR EXTERNAL NIC
# --------------------------------
# Associates the Network Security Group with each external NIC.
# This applies the NSG rules (allow all) to the FortiGate external interfaces.
##############################################################################################################

resource "azurerm_network_interface_security_group_association" "fgtifc1" {
  # count: One association per FortiGate NIC
  count                     = var.fgt_count
  
  # network_interface_id: The NIC to associate with the NSG
  # element() function safely gets the item at the given index
  # [*] is the splat expression - gets all IDs as a list
  network_interface_id      = element(azurerm_network_interface.fgtifc1[*].id, count.index)
  
  # network_security_group_id: The NSG to apply
  network_security_group_id = azurerm_network_security_group.fgtnsg.id
}


##############################################################################################################
# EXTERNAL LB BACKEND POOL ASSOCIATION
# ------------------------------------
# Adds each external NIC to the External Load Balancer's backend pool.
# This allows the ELB to distribute incoming traffic to all FortiGates.
##############################################################################################################

resource "azurerm_network_interface_backend_address_pool_association" "fgtifc1elbbackendpool" {
  # count: One association per FortiGate
  count                   = var.fgt_count
  
  # network_interface_id: Which NIC to add to the backend pool
  network_interface_id    = element(azurerm_network_interface.fgtifc1[*].id, count.index)
  
  # ip_configuration_name: Which IP configuration on the NIC
  # Must match the name in the NIC's ip_configuration block
  ip_configuration_name   = "interface1"
  
  # backend_address_pool_id: The External LB's backend pool
  backend_address_pool_id = azurerm_lb_backend_address_pool.elbbackend.id
}


##############################################################################################################
# NAT RULE ASSOCIATION - HTTPS MANAGEMENT
# ---------------------------------------
# Associates each external NIC with its corresponding HTTPS NAT rule.
# This enables direct HTTPS access to each FortiGate's management interface.
##############################################################################################################

resource "azurerm_network_interface_nat_rule_association" "fgtmgmthttps" {
  # count: One association per FortiGate
  count                 = var.fgt_count
  
  # network_interface_id: The external NIC receiving the NAT'd traffic
  network_interface_id  = element(azurerm_network_interface.fgtifc1[*].id, count.index)
  
  # ip_configuration_name: The IP configuration to use
  ip_configuration_name = "interface1"
  
  # nat_rule_id: The corresponding NAT rule for this FortiGate
  # FortiGate-0 gets NAT rule 0 (port 40030), FortiGate-1 gets rule 1 (port 40031), etc.
  nat_rule_id           = element(azurerm_lb_nat_rule.fgtmgmthttps[*].id, count.index)
}


##############################################################################################################
# NAT RULE ASSOCIATION - SSH MANAGEMENT
# -------------------------------------
# Associates each external NIC with its corresponding SSH NAT rule.
# This enables direct SSH access to each FortiGate's CLI.
##############################################################################################################

resource "azurerm_network_interface_nat_rule_association" "fgtmgmtssh" {
  # count: One association per FortiGate
  count                 = var.fgt_count
  
  # network_interface_id: The external NIC
  network_interface_id  = element(azurerm_network_interface.fgtifc1[*].id, count.index)
  
  # ip_configuration_name: The IP configuration
  ip_configuration_name = "interface1"
  
  # nat_rule_id: The SSH NAT rule for this FortiGate
  nat_rule_id           = element(azurerm_lb_nat_rule.fgtmgmtssh[*].id, count.index)
}


##############################################################################################################
# INTERNAL NETWORK INTERFACE (NIC2 / port2)
# -----------------------------------------
# This NIC connects FortiGate to the Internal subnet for LAN-side traffic.
# It's associated with:
# - Network Security Group (NSG)
# - Internal Load Balancer backend pool (for outbound traffic distribution)
##############################################################################################################

resource "azurerm_network_interface" "fgtifc2" {
  # count: Create one internal NIC per FortiGate VM
  count                 = var.fgt_count
  
  # name: Unique name for each internal NIC
  # Example: rw-az201-fgt-0-nic2, rw-az201-fgt-1-nic2
  name                  = "${var.prefix}-fgt-${count.index}-nic2"
  
  location              = azurerm_resource_group.resourcegroup.location
  resource_group_name   = azurerm_resource_group.resourcegroup.name
  
  # ip_forwarding_enabled: Also required on internal interface
  # FortiGate forwards traffic between external and internal interfaces
  ip_forwarding_enabled = true

  # ip_configuration: Internal interface settings
  ip_configuration {
    name                          = "interface2"
    
    # subnet_id: Internal subnet (10.100.2.0/24)
    subnet_id                     = azurerm_subnet.subnet2.id
    
    # Dynamic IP allocation
    private_ip_address_allocation = "Dynamic"
  }
}


##############################################################################################################
# NSG ASSOCIATION FOR INTERNAL NIC
# --------------------------------
# Associates the NSG with each internal NIC.
##############################################################################################################

resource "azurerm_network_interface_security_group_association" "fgtifc2" {
  count                     = var.fgt_count
  
  # Note: Using .*.id (old syntax) instead of [*].id - both work the same
  network_interface_id      = element(azurerm_network_interface.fgtifc2.*.id, count.index)
  network_security_group_id = azurerm_network_security_group.fgtnsg.id
}


##############################################################################################################
# INTERNAL LB BACKEND POOL ASSOCIATION (INTERNAL NIC)
# ---------------------------------------------------
# Associates each FortiGate's internal NIC (port2) to the Internal Load Balancer backend pool.
#
# This is CRITICAL for outbound traffic flow:
# 1. Protected VMs send traffic to Internal LB (via route table)
# 2. Internal LB distributes traffic to FortiGate internal interfaces (port2)
# 3. FortiGate inspects and forwards traffic to internet via external interface (port1)
#
# Without this association, the Internal LB would have no backends,
# and all outbound traffic from the protected subnet would fail.
##############################################################################################################

resource "azurerm_network_interface_backend_address_pool_association" "fgtifc2ilbbackendpool" {
  count                   = var.fgt_count
  network_interface_id    = element(azurerm_network_interface.fgtifc2[*].id, count.index)
  ip_configuration_name   = "interface2"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ilbbackend.id
}

##############################################################################################################
# NETWORK INTERFACE NOTES
# -----------------------
#
# WHY IP FORWARDING IS CRITICAL:
# By default, Azure drops traffic not destined for the NIC's own IP.
# FortiGate acts as a router - it receives traffic for other destinations.
# IP forwarding tells Azure: "This VM will forward traffic to other IPs"
#
# TERRAFORM COUNT AND ELEMENT():
# - count creates multiple instances: fgtifc1[0], fgtifc1[1], etc.
# - element(list, index) safely retrieves items from a list
# - [*].id is the "splat expression" - gets all IDs as a list
#   Example: azurerm_network_interface.fgtifc1[*].id returns ["id0", "id1", ...]
#
# NIC ORDERING IN VM:
# When attaching NICs to a VM, order matters:
# - First NIC (index 0) becomes the primary NIC
# - In FortiGate, NICs map to ports: NIC1=port1, NIC2=port2, etc.
#
# ACCELERATED NETWORKING:
# - Bypasses the host's virtual switch
# - Reduces latency and increases throughput
# - Not all VM sizes support it
# - Check: az vm list-skus --location <region> --all --query "[?capabilities[?name=='AcceleratedNetworkingEnabled' && value=='True']].name"
#
# REFERENCING NIC IPs:
# - External NIC IPs: azurerm_network_interface.fgtifc1[*].private_ip_address
# - Internal NIC IPs: azurerm_network_interface.fgtifc2[*].private_ip_address
# These are used in customdata.tpl to configure FortiGate interfaces
#
##############################################################################################################