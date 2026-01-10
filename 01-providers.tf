##############################################################################################################
#
#  TERRAFORM AND PROVIDER CONFIGURATION
#  =====================================
#
#  This file configures Terraform itself and the Azure Resource Manager (azurerm) provider.
#  The provider is what allows Terraform to communicate with Azure APIs.
#
##############################################################################################################

##############################################################################################################
# TERRAFORM BLOCK
# ---------------
# The terraform block configures Terraform's behavior and declares required providers.
# This must be defined before any resources can be created.
##############################################################################################################

terraform {
  # required_version: Specifies the minimum version of Terraform CLI needed to run this code
  # The ">=" means "this version or newer"
  # Using a version constraint helps ensure consistent behavior across team members
  required_version = ">= 0.13"
  
  # required_providers: Declares which providers this configuration depends on
  # Each provider must be declared here before it can be used
  required_providers {
    # azurerm: The Azure Resource Manager provider
    # This provider enables Terraform to create, update, and delete Azure resources
    azurerm = {
      # source: Where to download the provider from
      # "hashicorp/azurerm" means the official HashiCorp-maintained Azure provider
      # Format: <namespace>/<provider-name>
      source  = "hashicorp/azurerm"
      
      # version: Pin to a specific provider version for reproducibility
      # This ensures everyone on the team uses the same provider version
      # Avoiding unexpected behavior from provider updates
      version = "4.52.0"
    }
  }
}

##############################################################################################################
# AZURERM PROVIDER CONFIGURATION
# ------------------------------
# The provider block configures the Azure provider with authentication and settings.
# Multiple provider blocks can exist for multi-subscription or multi-region deployments.
##############################################################################################################

provider "azurerm" {
  # features: Required block (even if empty) that enables/disables certain provider behaviors
  # As of azurerm 2.0+, this block is mandatory
  # You can configure optional features like:
  #   - key_vault { purge_soft_delete_on_destroy = true }
  #   - virtual_machine { delete_os_disk_on_deletion = true }
  features {}
  
  # subscription_id: The Azure subscription where resources will be created
  # This value comes from the variables.tf file
  # You can find your subscription ID in the Azure Portal or via:
  #   az account list --output table
  subscription_id = var.subscription_id
}

##############################################################################################################
# AUTHENTICATION NOTE
# -------------------
# The azurerm provider supports multiple authentication methods:
#
# 1. Azure CLI (recommended for development):
#    - Run: az login
#    - Terraform will automatically use your CLI credentials
#
# 2. Service Principal with Client Secret:
#    provider "azurerm" {
#      client_id       = "00000000-0000-0000-0000-000000000000"
#      client_secret   = "your-client-secret"
#      tenant_id       = "00000000-0000-0000-0000-000000000000"
#      subscription_id = "00000000-0000-0000-0000-000000000000"
#    }
#
# 3. Managed Identity (for Azure-hosted automation):
#    provider "azurerm" {
#      use_msi = true
#    }
#
# 4. Environment Variables:
#    export ARM_CLIENT_ID="..."
#    export ARM_CLIENT_SECRET="..."
#    export ARM_TENANT_ID="..."
#    export ARM_SUBSCRIPTION_ID="..."
#
##############################################################################################################