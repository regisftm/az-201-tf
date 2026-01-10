##############################################################################################################
#
#  NETWORK SECURITY GROUPS (NSG)
#  =============================
#
#  Network Security Groups are Azure's built-in stateful firewall.
#  They filter traffic at the network layer (Layer 3/4) using rules based on:
#  - Source/Destination IP
#  - Source/Destination Port
#  - Protocol (TCP, UDP, ICMP, etc.)
#
#  NSG vs FORTIGATE:
#  -----------------
#  - NSG: Basic L3/L4 filtering, applied at subnet or NIC level
#  - FortiGate: Advanced L7 inspection, IPS, AV, SSL inspection, etc.
#
#  In this deployment, NSGs are set to "Allow All" because:
#  - FortiGate handles all security inspection
#  - NSG is required but shouldn't block FortiGate traffic
#  - Avoids double-filtering complexity
#
#  NOTE: In production, you might add NSG rules as a defense-in-depth layer.
#
##############################################################################################################


##############################################################################################################
# NETWORK SECURITY GROUP FOR FORTIGATES
# -------------------------------------
# This NSG is attached to all FortiGate network interfaces.
# It's configured to allow all traffic since FortiGate does the actual filtering.
##############################################################################################################

resource "azurerm_network_security_group" "fgtnsg" {
  # name: Descriptive name for the NSG
  name                = "${var.prefix}-fgt-nsg"
  
  # location: NSGs are regional resources
  location            = var.location
  
  # resource_group_name: The Resource Group containing this NSG
  resource_group_name = azurerm_resource_group.resourcegroup.name
}


##############################################################################################################
# NSG RULE: ALLOW ALL OUTBOUND
# ----------------------------
# Allows all outbound traffic from FortiGate interfaces.
# FortiGate needs unrestricted outbound access for:
# - Internet access for protected resources
# - FortiGuard updates (AV, IPS signatures)
# - Cloud connector communication
# - Management traffic
##############################################################################################################

resource "azurerm_network_security_rule" "fgtnsgallowallout" {
  # name: Rule identifier (must be unique within the NSG)
  name                        = "AllowAllOutbound"
  
  # resource_group_name: Must match the NSG's Resource Group
  resource_group_name         = azurerm_resource_group.resourcegroup.name
  
  # network_security_group_name: The NSG this rule belongs to
  # This creates a dependency - Terraform creates the NSG first
  network_security_group_name = azurerm_network_security_group.fgtnsg.name
  
  # priority: Rule evaluation order (100-4096, lower = higher priority)
  # Rules are evaluated in priority order; first match wins
  # 100 is high priority, ensuring this rule is evaluated early
  priority                    = 100
  
  # direction: Inbound or Outbound
  # This rule applies to traffic leaving the FortiGate interfaces
  direction                   = "Outbound"
  
  # access: Allow or Deny
  access                      = "Allow"
  
  # protocol: TCP, UDP, ICMP, * (any), or specific protocol number
  # Using "Tcp" here, but FortiGate typically needs all protocols
  protocol                    = "*"
  
  # source_port_range: Port(s) on the source (FortiGate side)
  # "*" means any source port
  source_port_range           = "*"
  
  # destination_port_range: Port(s) on the destination
  # "*" means any destination port
  destination_port_range      = "*"
  
  # source_address_prefix: Source IP range
  # "*" means any source IP (from the FortiGate interfaces)
  source_address_prefix       = "*"
  
  # destination_address_prefix: Destination IP range
  # "*" means any destination IP (anywhere on the internet)
  destination_address_prefix  = "*"
}


##############################################################################################################
# NSG RULE: ALLOW ALL INBOUND
# ---------------------------
# Allows all inbound traffic to FortiGate interfaces.
# FortiGate needs unrestricted inbound access for:
# - Management access (HTTPS, SSH via NAT rules)
# - Load balancer health probes
# - Incoming traffic from internet (through External LB)
# - Return traffic for outbound sessions
##############################################################################################################

resource "azurerm_network_security_rule" "fgtnsgallowallin" {
  name                        = "AllowAllInbound"
  resource_group_name         = azurerm_resource_group.resourcegroup.name
  network_security_group_name = azurerm_network_security_group.fgtnsg.name
  
  # priority: Same as outbound rule (100 is high priority)
  # Inbound and outbound rules are evaluated separately
  priority                    = 100
  
  # direction: Inbound means traffic coming TO the FortiGate
  direction                   = "Inbound"
  
  # Allow all inbound traffic
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}


##############################################################################################################
# NSG NOTES
# ---------
#
# DEFAULT NSG RULES:
# Azure creates implicit rules that you cannot delete:
# - Priority 65000: Allow VNet inbound (VirtualNetwork -> VirtualNetwork)
# - Priority 65001: Allow LB inbound (AzureLoadBalancer -> Any)
# - Priority 65500: Deny all inbound (Any -> Any)
# - Priority 65000: Allow VNet outbound (VirtualNetwork -> VirtualNetwork)
# - Priority 65001: Allow Internet outbound (Any -> Internet)
# - Priority 65500: Deny all outbound (Any -> Any)
#
# RULE PROCESSING:
# - Rules evaluated by priority (lowest number first)
# - First matching rule wins
# - If no rule matches, implicit deny at 65500
#
# NSG ASSOCIATION OPTIONS:
# - Subnet level: Applies to all NICs in the subnet
# - NIC level: Applies only to that specific NIC
# - Both: Rules from both NSGs are combined
#
# BEST PRACTICES:
# - Use descriptive rule names
# - Document the purpose of each rule
# - Use service tags (Internet, VirtualNetwork) when possible
# - Regularly audit NSG rules
#
# WHERE NSG IS ATTACHED (this deployment):
# NSG -> FortiGate NIC1 (external interface)
# NSG -> FortiGate NIC2 (internal interface)
# See: 09-fortigate-nics.tf for the associations
#
##############################################################################################################