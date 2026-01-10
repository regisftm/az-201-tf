##############################################################################################################
#
#  TERRAFORM OUTPUTS
#  =================
#
#  Outputs display useful information after Terraform completes.
#  They can also be used to pass values between Terraform modules.
#
#  VIEWING OUTPUTS:
#  ----------------
#  - After apply: Outputs display automatically
#  - Anytime: terraform output
#  - Specific output: terraform output deployment_summary
#  - JSON format: terraform output -json
#
#  USE CASES FOR OUTPUTS:
#  ----------------------
#  1. Display connection information (IPs, URLs)
#  2. Share values between Terraform modules
#  3. Integration with CI/CD pipelines
#  4. Documentation and operational reference
#
##############################################################################################################


##############################################################################################################
# DEPLOYMENT SUMMARY OUTPUT
# -------------------------
# This output renders a template file that provides a human-readable summary
# of the deployment, including connection information for each FortiGate.
#
# The templatefile() function reads summary.tpl and substitutes the variables
# with actual values from the Terraform state.
##############################################################################################################

output "deployment_summary" {
  # value: The content to output
  # templatefile() renders the summary.tpl template with these variables:
  value = templatefile("${path.module}/summary.tpl", {
    # username: The FortiGate admin username (for reference)
    username                     = var.username
    
    # location: The Azure region where resources are deployed
    location                     = var.location
    
    # elb_ipaddress: The Public IP address of the External Load Balancer
    # This is the main entry point for accessing FortiGates from the internet
    # data.azurerm_public_ip reads the IP after it's allocated
    elb_ipaddress                = data.azurerm_public_ip.elbpip.ip_address
    
    # fgt_ext_ips: List of all FortiGate external interface IPs
    # [*] is the splat expression - gets all private_ip_address values as a list
    # Example: ["10.100.1.4", "10.100.1.5"]
    fgt_ext_ips   = azurerm_network_interface.fgtifc1[*].private_ip_address
    
    # fgt_int_ips: List of all FortiGate internal interface IPs
    # Example: ["10.100.2.4", "10.100.2.5"]
    fgt_int_ips   = azurerm_network_interface.fgtifc2[*].private_ip_address
    
    # fgt_license_fortiflex: List of FortiFlex tokens (for reference)
    # Displayed in summary so you know which token went to which FortiGate
    fgt_license_fortiflex = var.fgt_byol_fortiflex_token
  })
}


##############################################################################################################
# OUTPUT NOTES
# ------------
#
# SENSITIVE OUTPUTS:
# If an output contains sensitive data (passwords, keys), mark it sensitive:
#   output "admin_password" {
#     value     = var.password
#     sensitive = true
#   }
# Sensitive outputs are hidden in CLI output but still stored in state.
#
# ADDITIONAL USEFUL OUTPUTS YOU MIGHT ADD:
#
# # Resource Group name
# output "resource_group_name" {
#   value = azurerm_resource_group.resourcegroup.name
# }
#
# # External Load Balancer Public IP
# output "external_lb_public_ip" {
#   value = data.azurerm_public_ip.elbpip.ip_address
# }
#
# # FortiGate Management URLs
# output "fortigate_management_urls" {
#   value = [for i in range(var.fgt_count) : 
#     "https://${data.azurerm_public_ip.elbpip.ip_address}:${40030 + i}/"]
# }
#
# # Internal Load Balancer IP
# output "internal_lb_ip" {
#   value = azurerm_lb.ilb.private_ip_address
# }
#
# # FortiGate External Interface IPs
# output "fortigate_external_ips" {
#   value = azurerm_network_interface.fgtifc1[*].private_ip_address
# }
#
# # FortiGate Internal Interface IPs  
# output "fortigate_internal_ips" {
#   value = azurerm_network_interface.fgtifc2[*].private_ip_address
# }
#
# USING OUTPUTS IN OTHER MODULES:
# If this is a child module, parent module can access outputs:
#   module "fortigate" {
#     source = "./fortigate-module"
#   }
#   # Access: module.fortigate.deployment_summary
#
##############################################################################################################