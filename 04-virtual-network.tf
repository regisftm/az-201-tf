##############################################################################################################
#
#  VIRTUAL NETWORK AND SUBNETS
#  ===========================
#
#  The Virtual Network (VNet) is the foundation of Azure networking.
#  It provides an isolated network environment where you control:
#  - IP address ranges
#  - Subnets
#  - Route tables
#  - Network security
#
#  NETWORK ARCHITECTURE:
#  ---------------------
#
#  +-----------------------------------------------------------------------------------+
#  |  Virtual Network: 10.100.0.0/16                                                   |
#  |                                                                                   |
#  |  +---------------------------+  +---------------------------+                     |
#  |  | Subnet 1 (External)       |  | Subnet 2 (Internal)       |                     |
#  |  | 10.100.1.0/24             |  | 10.100.2.0/24             |                     |
#  |  |                           |  |                           |                     |
#  |  | - FortiGate port1 (WAN)   |  | - FortiGate port2 (LAN)   |                     |
#  |  | - External Load Balancer  |  | - Internal Load Balancer  |                     |
#  |  | - Public IP attachment    |  |                           |                     |
#  |  +---------------------------+  +---------------------------+                     |
#  |                                                                                   |
#  |  +---------------------------+                                                    |
#  |  | Subnet 3 (Protected)      |                                                    |
#  |  | 10.100.3.0/24             |                                                    |
#  |  |                           |                                                    |
#  |  | - Backend servers/VMs     |                                                    |
#  |  | - Application workloads   |                                                    |
#  |  | - Route table attached    |                                                    |
#  |  +---------------------------+                                                    |
#  |                                                                                   |
#  +-----------------------------------------------------------------------------------+
#
##############################################################################################################


##############################################################################################################
# VIRTUAL NETWORK
# ---------------
# The VNet is the top-level networking container in Azure.
# All subnets, NICs, and internal routing happen within the VNet.
##############################################################################################################

resource "azurerm_virtual_network" "vnet" {
  # name: The display name for this VNet
  # Must be unique within the Resource Group
  name                = "${var.prefix}-vnet"
  
  # address_space: The IP address range(s) for this VNet
  # Specified in CIDR notation as a list (you can have multiple ranges)
  # Example: 10.100.0.0/16 provides 65,536 IP addresses
  address_space       = [var.vnet]
  
  # location: Must match or be compatible with the Resource Group location
  # Using the Resource Group's location ensures consistency
  location            = azurerm_resource_group.resourcegroup.location
  
  # resource_group_name: The Resource Group to place this VNet in
  # References the Resource Group created earlier
  resource_group_name = azurerm_resource_group.resourcegroup.name
}


##############################################################################################################
# SUBNET 1: EXTERNAL (Untrust / WAN)
# ----------------------------------
# This subnet hosts the FortiGate external interfaces (port1).
# Traffic from the internet enters through this subnet via the External Load Balancer.
#
# PURPOSE:
# - Receive inbound traffic from the internet
# - External Load Balancer frontend
# - FortiGate management access (NAT rules)
##############################################################################################################

resource "azurerm_subnet" "subnet1" {
  # name: Descriptive name indicating the subnet's purpose
  name                 = "${var.prefix}-subnet-fgt-external"
  
  # resource_group_name: Must be in the same Resource Group as the VNet
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  
  # virtual_network_name: The VNet this subnet belongs to
  # Creates an implicit dependency - Terraform knows to create the VNet first
  virtual_network_name = azurerm_virtual_network.vnet.name
  
  # address_prefixes: The IP range for this subnet (must be within VNet range)
  # Using var.subnet["0"] = "10.100.1.0/24"
  # This gives us IPs from 10.100.1.0 to 10.100.1.255
  # Azure reserves 5 IPs: .0 (network), .1-.3 (Azure services), .255 (broadcast)
  address_prefixes     = [var.subnet["0"]]
}


##############################################################################################################
# SUBNET 2: INTERNAL (Trust / LAN)
# --------------------------------
# This subnet hosts the FortiGate internal interfaces (port2).
# Traffic to/from protected resources flows through this subnet.
#
# PURPOSE:
# - FortiGate internal interfaces
# - Internal Load Balancer frontend
# - Gateway for protected subnet traffic
##############################################################################################################

resource "azurerm_subnet" "subnet2" {
  name                 = "${var.prefix}-subnet-fgt-internal"
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  
  # Using var.subnet["1"] = "10.100.2.0/24"
  address_prefixes     = [var.subnet["1"]]
}


##############################################################################################################
# SUBNET 3: PROTECTED (Backend / Workloads)
# -----------------------------------------
# This subnet hosts the protected resources (servers, applications, etc.)
# All traffic from this subnet is routed through the FortiGate for inspection.
#
# PURPOSE:
# - Backend servers and applications
# - Protected workloads
# - All egress traffic routed through Internal Load Balancer -> FortiGate
##############################################################################################################

resource "azurerm_subnet" "subnet3" {
  name                 = "${var.prefix}-subnet-protected"
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  
  # Using var.subnet["2"] = "10.100.3.0/24"
  address_prefixes     = [var.subnet["2"]]
}


##############################################################################################################
# SUBNET-ROUTE TABLE ASSOCIATION
# ------------------------------
# This associates the Protected subnet with a custom route table.
# The route table (defined in 05-route-tables.tf) forces all traffic
# through the Internal Load Balancer, which distributes it to FortiGates.
##############################################################################################################

resource "azurerm_subnet_route_table_association" "subnet3rt" {
  # subnet_id: The subnet to associate with the route table
  subnet_id      = azurerm_subnet.subnet3.id
  
  # route_table_id: The route table to apply to this subnet
  # This reference creates a dependency on the route table resource
  route_table_id = azurerm_route_table.protectedaroute.id

  # lifecycle: Special meta-argument to control resource behavior
  lifecycle {
    # ignore_changes: Prevents Terraform from reverting manual changes
    # Useful when route tables might be modified by Azure or other automation
    # Without this, Terraform would try to "fix" any external changes
    ignore_changes = [route_table_id]
  }
}


##############################################################################################################
# SUBNET REFERENCE GUIDE
# ----------------------
#
# To reference these subnets in other resources:
#
# External subnet ID:   azurerm_subnet.subnet1.id
# Internal subnet ID:   azurerm_subnet.subnet2.id
# Protected subnet ID:  azurerm_subnet.subnet3.id
#
# AZURE RESERVED IPs (per subnet):
# .0   - Network address
# .1   - Default gateway (Azure)
# .2   - Azure DNS
# .3   - Azure DNS
# .255 - Broadcast address
#
# So in a /24 subnet, you have 251 usable IPs (256 - 5 reserved)
#
##############################################################################################################