##############################################################################################################
#
#  AZURE RESOURCE GROUP
#  ====================
#
#  A Resource Group is a logical container for Azure resources.
#  All resources in this deployment will be placed in this single Resource Group.
#
#  WHY USE A RESOURCE GROUP?
#  -------------------------
#  - Organize related resources together
#  - Apply common policies and access controls
#  - View aggregated costs for the group
#  - Delete all resources at once by deleting the Resource Group
#  - Resources in the same group should share the same lifecycle
#
##############################################################################################################

##############################################################################################################
# RESOURCE GROUP
# --------------
# This is typically the first resource created because most other Azure resources
# require a Resource Group to be specified.
##############################################################################################################

resource "azurerm_resource_group" "resourcegroup" {
  # name: The name of the Resource Group
  # Must be unique within your subscription
  # Using var.prefix ensures uniqueness and easy identification
  name     = "${var.prefix}-rg"
  
  # location: The Azure region where the Resource Group metadata is stored
  # Note: Resources within the group can be in different regions,
  # but it's best practice to keep them in the same region for performance
  location = var.location
}

##############################################################################################################
# RESOURCE GROUP NOTES
# --------------------
#
# NAMING CONVENTIONS:
# - Use lowercase letters, numbers, hyphens, and underscores
# - Start with a letter
# - Maximum 90 characters
#
# REFERENCING THIS RESOURCE:
# Other resources reference this Resource Group using:
#   - azurerm_resource_group.resourcegroup.name     (the name)
#   - azurerm_resource_group.resourcegroup.location (the location)
#
# TERRAFORM STATE:
# Terraform tracks this resource in its state file. If you manually delete
# the Resource Group in Azure Portal, run "terraform refresh" to sync state.
#
# DESTROY BEHAVIOR:
# When you run "terraform destroy", this Resource Group and ALL resources
# within it will be deleted. This is a convenient way to clean up.
#
##############################################################################################################