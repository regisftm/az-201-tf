##############################################################################################################
#
#  FORTIGATE VIRTUAL MACHINES
#  ==========================
#
#  This file creates the FortiGate firewall VMs - the core of the deployment.
#  Each FortiGate is deployed as an Azure Linux VM using the FortiGate marketplace image.
#
#  FORTIGATE VM COMPONENTS:
#  ------------------------
#
#  +------------------------------------------+
#  |            FortiGate VM                  |
#  |                                          |
#  |  +------------------------------------+  |
#  |  | OS Disk                            |  |  <-- Boot disk with FortiOS
#  |  | (Standard_LRS, 2 GB default)       |  |
#  |  +------------------------------------+  |
#  |                                          |
#  |  +------------------------------------+  |
#  |  | Data Disk (50 GB)                  |  |  <-- Logging, cache, etc.
#  |  | (Attached separately)              |  |
#  |  +------------------------------------+  |
#  |                                          |
#  |  +---------------+ +----------------+    |
#  |  | NIC1 (port1)  | | NIC2 (port2)   |    |  <-- Network interfaces
#  |  | External      | | Internal       |    |
#  |  +---------------+ +----------------+    |
#  |                                          |
#  |  +------------------------------------+  |
#  |  | Custom Data (Bootstrap Config)    |  |  <-- Day-0 configuration
#  |  +------------------------------------+  |
#  |                                          |
#  +------------------------------------------+
#
##############################################################################################################


##############################################################################################################
# AVAILABILITY SET
# ----------------
# An Availability Set ensures FortiGate VMs are distributed across:
# - Fault Domains: Different physical racks (protects against hardware failure)
# - Update Domains: Different update groups (protects against planned maintenance)
#
# This provides high availability - both FortiGates won't fail simultaneously.
##############################################################################################################

resource "azurerm_availability_set" "fgtavset" {
  # name: Name of the Availability Set
  name                = "${var.prefix}-fgt-availabilityset"
  
  # location: Must be in the same region as the VMs
  location            = var.location
  
  # managed: Use Azure Managed Disks (recommended)
  # Required when VMs use managed disks
  managed             = true
  
  # resource_group_name: The Resource Group for this resource
  resource_group_name = azurerm_resource_group.resourcegroup.name
}


##############################################################################################################
# FORTIGATE VIRTUAL MACHINES
# --------------------------
# The main FortiGate VMs using Azure's Linux VM resource.
# FortiGate runs on a hardened Linux kernel, hence azurerm_linux_virtual_machine.
##############################################################################################################

resource "azurerm_linux_virtual_machine" "fgtvm" {
  # count: Number of FortiGate VMs to create
  # count.index = 0, 1, 2... for each VM
  count                 = var.fgt_count
  
  # name: Unique name for each FortiGate VM
  # Example: rw-az201-fgt-0, rw-az201-fgt-1
  name                  = "${var.prefix}-fgt-${count.index}"
  
  # location: Region for the VM
  location              = azurerm_resource_group.resourcegroup.location
  
  # resource_group_name: Resource Group containing the VM
  resource_group_name   = azurerm_resource_group.resourcegroup.name
  
  # network_interface_ids: NICs attached to this VM (ORDER MATTERS!)
  # First NIC becomes port1 (external), second becomes port2 (internal)
  # Using element() to get the corresponding NIC for each FortiGate
  network_interface_ids = ["${element(azurerm_network_interface.fgtifc1[*].id, count.index)}", "${element(azurerm_network_interface.fgtifc2[*].id, count.index)}"]
  
  # size: Azure VM size (determines CPU, RAM, network bandwidth)
  # Standard_B2s: 2 vCPU, 4 GB RAM (good for testing)
  # For production, consider Standard_F4s_v2 or larger
  size                  = var.fgt_vmsize
  
  # availability_set_id: Place VM in the Availability Set for HA
  availability_set_id   = azurerm_availability_set.fgtavset.id

  ##############################################################################################################
  # MANAGED IDENTITY
  # ----------------
  # Enables the VM to authenticate to Azure services without storing credentials.
  # FortiGate uses this for the Azure SDN Connector to:
  # - Read Azure resource information
  # - Update route tables
  # - Manage Public IPs
  # "SystemAssigned" creates an identity automatically managed by Azure
  ##############################################################################################################
  identity {
    type = "SystemAssigned"
  }

  ##############################################################################################################
  # SOURCE IMAGE REFERENCE
  # ----------------------
  # Specifies the FortiGate marketplace image to use.
  # Azure Marketplace images are identified by: publisher/offer/sku/version
  ##############################################################################################################
  source_image_reference {
    # publisher: The image publisher (Fortinet)
    publisher = "fortinet"
    
    # offer: The product offering
    offer     = "fortinet_fortigate-vm_v5"
    
    # sku: The specific SKU (PAYG vs BYOL)
    # - fortinet_fg-vm_payg_2023: Pay-As-You-Go
    # - fortinet_fg-vm: BYOL
    # - fortinet_fg-vm_g2: BYOL with Gen2 support
    sku       = var.fgt_image_sku
    
    # version: FortiOS version (e.g., "7.6.4" or "latest")
    version   = var.fgt_version
  }

  ##############################################################################################################
  # MARKETPLACE PLAN
  # ----------------
  # Required for Azure Marketplace images.
  # Accepts the marketplace terms and pricing.
  # Must match the source_image_reference values.
  ##############################################################################################################
  plan {
    publisher = "fortinet"
    product   = "fortinet_fortigate-vm_v5"
    name      = var.fgt_image_sku
  }

  ##############################################################################################################
  # OS DISK
  # -------
  # The boot disk containing FortiOS.
  # FortiGate has minimal OS disk requirements (~2 GB).
  ##############################################################################################################
  os_disk {
    # name: Unique name for each FortiGate's OS disk
    name                 = "${var.prefix}-fgt-${count.index}-osdisk"
    
    # caching: Disk caching setting
    # - None: No caching
    # - ReadOnly: Cache reads only
    # - ReadWrite: Cache both reads and writes (best for OS disks)
    caching              = "ReadWrite"
    
    # storage_account_type: Disk performance tier
    # - Standard_LRS: Standard HDD (cheapest)
    # - StandardSSD_LRS: Standard SSD
    # - Premium_LRS: Premium SSD (best performance)
    # Standard_LRS is sufficient for FortiGate OS disk
    storage_account_type = "Standard_LRS"
  }

  ##############################################################################################################
  # AUTHENTICATION
  # --------------
  # Credentials for accessing the FortiGate VM.
  # These are used for both SSH and web GUI access.
  ##############################################################################################################
  
  # admin_username: The administrator username
  admin_username                  = var.username
  
  # admin_password: The administrator password
  # WARNING: For production, use Azure Key Vault or secrets management
  admin_password                  = var.password
  
  # disable_password_authentication: Allow password auth (not just SSH keys)
  # Set to false to enable password authentication
  # FortiGate uses password auth for GUI and initial setup
  disable_password_authentication = false
  
  ##############################################################################################################
  # CUSTOM DATA (BOOTSTRAP CONFIGURATION)
  # -------------------------------------
  # Custom data is passed to the VM at first boot (cloud-init).
  # FortiGate uses this for Day-0 configuration - the initial setup.
  #
  # The templatefile() function:
  # 1. Reads the customdata.tpl file
  # 2. Substitutes variables with actual values
  # 3. Returns the rendered configuration
  #
  # base64encode() converts the config to Base64 (required by Azure)
  ##############################################################################################################
  custom_data = base64encode(templatefile("${path.module}/customdata.tpl", {
    # VM name for hostname configuration
    fgt_vm_name           = "${var.prefix}-fgt-${count.index}"
    
    # FortiFlex license token for this specific FortiGate
    fgt_license_fortiflex = var.fgt_byol_fortiflex_token[count.index]
    
    # Administrator username
    fgt_username          = var.username
    
    # External interface (port1) configuration
    # element() gets the IP for this specific FortiGate
    fgt_external_ipaddr   = element(azurerm_network_interface.fgtifc1[*].private_ip_address, count.index)
    fgt_external_mask     = cidrnetmask(var.subnet["0"])  # Converts "10.100.1.0/24" to "255.255.255.0"
    fgt_external_gw       = cidrhost(var.subnet["0"], 1)  # Gets first host IP (Azure gateway): 10.100.1.1
    
    # Internal interface (port2) configuration
    fgt_internal_ipaddr   = element(azurerm_network_interface.fgtifc2[*].private_ip_address, count.index)
    fgt_internal_mask     = cidrnetmask(var.subnet["1"])
    fgt_internal_gw       = cidrhost(var.subnet["1"], 1)
    
    # HA peer IPs - all internal interface IPs for FGSP communication
    fgt_ha_peerip         = azurerm_network_interface.fgtifc2[*].private_ip_address
    
    # Protected network CIDR - for firewall policies
    fgt_protected_net     = var.subnet["2"]
    
    # VNet CIDR - for routing configuration
    vnet_network          = var.vnet
  }))

  ##############################################################################################################
  # BOOT DIAGNOSTICS
  # ----------------
  # Enables serial console and boot screenshot for troubleshooting.
  # Empty block uses Azure-managed storage account (simplest option).
  # You can specify a custom storage account if needed.
  ##############################################################################################################
  boot_diagnostics {
  }

  # tags: Metadata tags for resource organization and cost tracking
  tags = var.fortinet_tags
}


##############################################################################################################
# DATA DISK
# ---------
# Additional storage for FortiGate logging, caching, and local storage.
# FortiGate can use this for:
# - Local logging (if not using FortiAnalyzer)
# - Firmware images for upgrades
# - Quarantine storage
# - Cache for FortiGuard updates
##############################################################################################################

resource "azurerm_managed_disk" "fgtvm-datadisk" {
  # count: One data disk per FortiGate
  count                = var.fgt_count
  
  # name: Unique name for each data disk
  name                 = "${var.prefix}-fgt-${count.index}-datadisk"
  
  location             = azurerm_resource_group.resourcegroup.location
  resource_group_name  = azurerm_resource_group.resourcegroup.name
  
  # storage_account_type: Disk type (Standard_LRS for logging is fine)
  storage_account_type = "Standard_LRS"
  
  # create_option: How to create the disk
  # - Empty: Create a blank disk
  # - Copy: Copy from another disk
  # - Import: Import from a VHD
  create_option        = "Empty"
  
  # disk_size_gb: Size of the disk in GB
  # 50 GB is usually sufficient for logging
  disk_size_gb         = 50
}


##############################################################################################################
# DATA DISK ATTACHMENT
# --------------------
# Attaches the data disk to the FortiGate VM.
# Terraform manages this separately from disk creation for flexibility.
##############################################################################################################

resource "azurerm_virtual_machine_data_disk_attachment" "fgtvm-datadisk-attach" {
  # count: One attachment per FortiGate
  count              = var.fgt_count
  
  # managed_disk_id: The data disk to attach
  managed_disk_id    = element(azurerm_managed_disk.fgtvm-datadisk[*].id, count.index)
  
  # virtual_machine_id: The VM to attach the disk to
  virtual_machine_id = element(azurerm_linux_virtual_machine.fgtvm[*].id, count.index)
  
  # lun: Logical Unit Number (disk slot)
  # LUN 0 is the first data disk slot
  # FortiGate will see this as an additional drive
  lun                = 0
  
  # caching: Disk caching for the data disk
  # ReadWrite is good for logging workloads
  caching            = "ReadWrite"
}


##############################################################################################################
# FORTIGATE VM NOTES
# ------------------
#
# TERRAFORM FUNCTIONS USED:
# - count: Creates multiple instances (fgtvm[0], fgtvm[1], ...)
# - element(list, index): Safely gets item from list at index
# - cidrnetmask("10.0.0.0/24"): Returns "255.255.255.0"
# - cidrhost("10.0.0.0/24", 1): Returns "10.0.0.1" (host #1 in subnet)
# - base64encode(): Converts string to Base64
# - templatefile(): Renders a template with variables
#
# FORTIGATE LICENSING OPTIONS:
# 1. PAYG (Pay-As-You-Go): License included in Azure hourly cost
# 2. BYOL (Bring Your Own License): Use existing Fortinet licenses
# 3. FortiFlex: Flexible points-based licensing
#
# CUSTOMDATA BOOTSTRAP:
# - Runs once at first boot
# - Configures interfaces, routing, basic settings
# - Can apply license (FortiFlex token)
# - Cannot be changed after VM creation (must redeploy)
#
# POST-DEPLOYMENT CONFIGURATION:
# After Terraform deploys, you may need to:
# 1. Configure firewall policies (allow traffic)
# 2. Set up FortiGuard connections
# 3. Configure logging (FortiAnalyzer, syslog)
# 4. Tune performance settings
# 5. Configure additional features (AV, IPS, Web Filter)
#
# TROUBLESHOOTING:
# - Serial console: Azure Portal > VM > Boot diagnostics
# - Check customdata: /var/log/cloud-init-output.log
# - FortiGate CLI: "diagnose debug config-error-log read"
#
##############################################################################################################