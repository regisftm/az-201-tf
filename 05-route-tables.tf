##############################################################################################################
#
#  ROUTE TABLES
#  ============
#
#  Route tables control how network traffic flows within the Virtual Network.
#  By default, Azure routes traffic automatically between subnets.
#  Custom route tables override this behavior to force traffic through FortiGate.
#
#  WHY USE CUSTOM ROUTES?
#  ----------------------
#  Without custom routes, traffic between Azure subnets bypasses the FortiGate.
#  To inspect and filter all traffic, we need User Defined Routes (UDRs) that
#  redirect traffic to the FortiGate (via the Internal Load Balancer).
#
#  TRAFFIC FLOW WITH CUSTOM ROUTES:
#  --------------------------------
#
#  [Protected VM] ---> [Route Table] ---> [Internal LB] ---> [FortiGate] ---> [Internet]
#                      (next hop = ILB)   (distributes)      (inspects)
#
#  [Protected VM] ---> [Route Table] ---> [Internal LB] ---> [FortiGate] ---> [Other VNet]
#                      (next hop = ILB)   (distributes)      (inspects)
#
##############################################################################################################


##############################################################################################################
# ROUTE TABLE FOR PROTECTED SUBNET
# --------------------------------
# This route table is attached to the Protected subnet (subnet3).
# It ensures all outbound traffic from protected workloads goes through FortiGate.
##############################################################################################################

resource "azurerm_route_table" "protectedaroute" {
  # name: Descriptive name for the route table
  name                = "${var.prefix}-rt-protected"
  
  # location: Route tables are regional resources
  location            = var.location
  
  # resource_group_name: The Resource Group containing this route table
  resource_group_name = azurerm_resource_group.resourcegroup.name
  
  ##############################################################################################################
  # ROUTE: Default Route (Internet Traffic)
  # -----------------------------------------
  # Forces all internet-bound traffic (0.0.0.0/0) through the FortiGate.
  # This is critical for:
  # - Inspecting outbound traffic
  # - Applying security policies
  # - NAT for internet access
  # - Logging and monitoring
  ##############################################################################################################
  route {
    name                   = "to_internet"
    
    # address_prefix: 0.0.0.0/0 is the "default route" - matches any destination
    # not covered by more specific routes
    address_prefix         = "0.0.0.0/0"
    
    # next_hop_type: Send to FortiGate via Internal Load Balancer
    next_hop_type          = "VirtualAppliance"
    
    # next_hop_in_ip_address: Internal Load Balancer IP
    # Traffic flows: Protected VM -> ILB -> FortiGate -> Internet
    next_hop_in_ip_address = azurerm_lb.ilb.private_ip_address
  }
}


##############################################################################################################
# ROUTE TABLE NOTES
# -----------------
#
# ROUTE PRIORITY:
# Azure selects routes based on longest prefix match:
# - /32 (most specific) takes priority over /24 over /16 over /0 (least specific)
# - If prefixes are equal, UDR > BGP > System routes
#
# EXAMPLE TRAFFIC FLOW:
# VM (10.100.3.10) wants to reach 8.8.8.8 (Google DNS):
# 1. Check routes: 8.8.8.8 doesn't match 10.100.0.0/16 or 10.100.3.0/24
# 2. Matches 0.0.0.0/0 (default route)
# 3. Forward to Internal LB (next_hop_in_ip_address)
# 4. ILB sends to FortiGate
# 5. FortiGate inspects and forwards to internet
#
# COMMON ISSUES:
# - Missing routes can cause traffic to bypass FortiGate
# - Incorrect next_hop_in_ip_address causes black hole
# - Asymmetric routing if return traffic doesn't go through FortiGate
#
# TROUBLESHOOTING:
# - Azure Portal: Network Watcher > Next hop
# - Azure CLI: az network nic show-effective-route-table
#
##############################################################################################################