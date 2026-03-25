##############################################################################################################
#
#  INPUT VARIABLES
#  ================
#
#  Variables allow you to parameterize your Terraform configuration.
#  This makes the code reusable across different environments (dev, staging, prod).
#
#  VARIABLE SYNTAX:
#  ----------------
#  variable "name" {
#    description = "What this variable is for"
#    type        = string | number | bool | list | map | object
#    default     = "optional default value"
#    sensitive   = true | false  # Hides value in logs
#    validation  { ... }         # Optional validation rules
#  }
#
#  WAYS TO SET VARIABLE VALUES (in order of precedence):
#  -----------------------------------------------------
#  1. Command line: terraform apply -var="prefix=myproject"
#  2. Variable file: terraform apply -var-file="prod.tfvars"
#  3. Environment variable: export TF_VAR_prefix="myproject"
#  4. Default value in this file
#  5. Interactive prompt (if no default and not provided)
#
##############################################################################################################


##############################################################################################################
# GENERAL DEPLOYMENT SETTINGS
# ---------------------------
# These variables control the basic naming and location of all resources.
##############################################################################################################

variable "prefix" {
  # The prefix is prepended to all resource names to:
  # - Ensure unique names across Azure
  # - Group related resources together
  # - Easily identify resources belonging to this deployment
  description = "Added name to each deployed resource"
  default = "rw-az201-sxx"
}

variable "location" {
  # Azure region where all resources will be deployed
  # Full list of regions: az account list-locations --output table
  # Common choices: eastus, westus2, canadacentral, westeurope
  # Choose based on: proximity to users, compliance requirements, service availability
  description = "Azure region"
  default     = "canadacentral"
}

variable "subscription_id" {
  # The Azure subscription ID where resources will be created
  # Find this in Azure Portal > Subscriptions, or run: az account show
  # IMPORTANT: Replace with your own subscription ID!
  description = "Azure subscription ID where all resources will be deployed"
}


##############################################################################################################
# AUTHENTICATION CREDENTIALS
# --------------------------
# Credentials for accessing the FortiGate VMs.
# WARNING: For production, use secrets management (Azure Key Vault, HashiCorp Vault)
#          Never commit real credentials to version control!
##############################################################################################################

variable "username" {
  # The administrator username for FortiGate VMs
  # This will be used for both SSH and GUI access
  description = "Administrator username for FortiGate VMs (used for SSH and web GUI access)"
  default = "fortiuser"
}

variable "password" {
  # The administrator password for FortiGate VMs
  # Password requirements:
  # - Minimum 8 characters
  # - At least one uppercase, lowercase, number, and special character
  # TIP: For production, use: sensitive = true
  description = "Administrator password for FortiGate VMs (used for SSH and web GUI access)"
}


##############################################################################################################
# FORTIGATE VM CONFIGURATION
# --------------------------
# These variables control the FortiGate virtual machine deployment settings.
##############################################################################################################

variable "fgt_count" {
  # Number of FortiGate VMs to deploy in the Active/Active cluster
  # Minimum: 1 (single FortiGate, no redundancy)
  # Recommended: 2 (for high availability)
  # Maximum: Limited by Azure subscription quotas and load balancer backend pool limits
  description = "Number of FortiGate VMs to deploy"
  default     = 2
}

variable "fgt_image_sku" {
  # The Azure Marketplace SKU for the FortiGate image
  # Available options:
  #   - "fortinet_fg-vm_payg_2023"  : Pay-As-You-Go (hourly billing, includes license)
  #   - "fortinet_fg-vm"            : BYOL (Bring Your Own License)
  #   - "fortinet_fg-vm_g2"         : BYOL with Gen2 VM support
  # PAYG is easier for testing; BYOL is more cost-effective for production
  description = "Azure Marketplace default image sku hourly (PAYG 'fortinet_fg-vm_payg_2023') or byol (Bring your own license 'fortinet_fg-vm')"
  default     = "fortinet_fg-vm_g2"
}

variable "fgt_version" {
  # FortiOS version to deploy
  # Use "latest" for the most recent version, or specify exact version like "7.6.4"
  # Check available versions: az vm image list --publisher fortinet --all --output table
  # TIP: Pin to specific version for production stability
  description = "FortiGate version by default the 'latest' available version in the Azure Marketplace is selected"
  default     = "7.6.4"
}

variable "fgt_vmsize" {
  # Azure VM size (instance type) for FortiGate VMs
  # The VM size determines: vCPUs, memory, network bandwidth, disk throughput
  # Common choices for FortiGate:
  #   - Standard_B2s    : 2 vCPU, 4 GB RAM (dev/test, low traffic)
  #   - Standard_F2s_v2 : 2 vCPU, 4 GB RAM (production, moderate traffic)
  #   - Standard_F4s_v2 : 4 vCPU, 8 GB RAM (production, high traffic)
  #   - Standard_F8s_v2 : 8 vCPU, 16 GB RAM (enterprise, very high traffic)
  # FortiGate sizing guide: https://docs.fortinet.com/document/fortigate-public-cloud/7.6.0/azure-administration-guide/562841/instance-type-support
  description = "Azure VM size for FortiGate instances (determines vCPU, RAM, and network throughput)"
  default = "Standard_B2s"
}

variable "fgt_byol_fortiflex_token" {
  # FortiFlex license tokens for BYOL deployments
  # FortiFlex provides flexible, consumption-based licensing
  # Each FortiGate VM needs its own unique token
  # IMPORTANT: The number of tokens must match fgt_count!
  # Get tokens from: FortiCare Portal > FortiFlex > Programs
  type        = list(string)
  description = "FortiFlex license tokens for each FortiGate."
}

variable "fgt_accelerated_networking" {
  # Enable Azure Accelerated Networking for FortiGate NICs
  # Accelerated Networking provides:
  #   - Lower latency
  #   - Higher packets per second
  #   - Lower CPU utilization
  # Requirements: Supported VM size (most F-series and D-series)
  # Note: Not all VM sizes support this feature
  description = "Enables Accelerated Networking for the network interfaces of the FortiGate"
  default     = "false"
}


##############################################################################################################
# NETWORK CONFIGURATION
# ---------------------
# These variables define the IP address scheme for the virtual network.
# The network is divided into subnets for different purposes.
##############################################################################################################

variable "vnet" {
  # The overall address space for the Virtual Network (VNet)
  # This should be large enough to contain all subnets
  # Common choices: /16 (65,536 addresses) or /8 (16 million addresses)
  # CIDR notation: 10.100.0.0/16 means IPs from 10.100.0.0 to 10.100.255.255
  description = "Virtual Network address space in CIDR notation (must contain all subnets)"
  default     = "10.100.0.0/16"
}

variable "subnet" {
  # Subnet definitions within the VNet
  # Using a map allows easy reference by key (0, 1, 2) in other resources
  #
  # SUBNET LAYOUT:
  # --------------
  # subnet[0] - External/Untrust: FortiGate external interfaces (facing internet)
  # subnet[1] - Internal/Trust:   FortiGate internal interfaces (facing internal LB)
  # subnet[2] - Protected:        Backend workloads protected by FortiGate
  #
  # IMPORTANT: Subnets must not overlap and must be within the VNet range
  type        = map(string)
  description = "Map of subnet CIDR ranges: 0=External (WAN), 1=Internal (LAN), 2=Protected (workloads)"

  default = {
    "0" = "10.100.1.0/24"  # External - 254 usable IPs (Azure reserves 5)
    "1" = "10.100.2.0/24"  # Internal - 254 usable IPs
    "2" = "10.100.3.0/24"  # Protected - 254 usable IPs
  }
}

variable "subnetmask" {
  # Subnet masks in CIDR notation (number of bits)
  # /24 = 255.255.255.0 = 256 addresses (254 usable in Azure)
  # This is kept separate for use in some configurations that need just the mask
  type        = map(string)
  description = "Map of subnet mask lengths in CIDR notation: 0=External, 1=Internal, 2=Protected"

  default = {
    "0" = "24" # External
    "1" = "24" # Internal
    "2" = "24" # Protected
  }
}


##############################################################################################################
# RESOURCE TAGS
# -------------
# Tags are key-value pairs attached to Azure resources for organization and cost tracking.
##############################################################################################################

variable "fortinet_tags" {
  # Tags applied to all resources in this deployment
  # Common uses:
  #   - Cost allocation (CostCenter, Project)
  #   - Ownership (Owner, Team)
  #   - Lifecycle (Environment, ExpectedUseThrough)
  #   - Automation (VMState for start/stop automation)
  type = map(string)
  description = "Resource tags applied to all Azure resources for organization, cost tracking, and automation"
  default = {
    Publisher : "Fortinet"
    Name : "Regis Martins"
    Username: "rtxxxx@fortinet-us.com"
    ExpectedUseThrough: "2026-12"
    CostoCenter: "xxxx"
    VMState: "AlwaysOn"
  }
}