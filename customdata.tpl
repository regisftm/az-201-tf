################################################################################
#
#  FORTIGATE BOOTSTRAP CONFIGURATION TEMPLATE
#  ==========================================
#
#  This file is a Terraform template that generates the FortiGate Day-0 
#  configuration.
#  It's passed to the VM via Azure custom_data and executed at first boot.
#
#  TEMPLATE SYNTAX:
#  ----------------
#  $${variable_name}          - Substitutes the variable value
#  %%{ if condition }...%%{ endif }  - Conditional blocks
#  %%{ for item in list }...%%{ endfor }  - Loop constructs
#
#  MIME MULTIPART FORMAT:
#  ----------------------
#  FortiGate expects custom_data in MIME multipart format with:
#  - Part 1: FortiGate CLI configuration
#  - Part 2: License file (optional, for BYOL/FortiFlex)
#
#  The boundary string "===FortGateConfig===" separates the parts.
#
################################################################################

Content-Type: multipart/mixed; boundary="===FortGateConfig==="
MIME-Version: 1.0

--===FortGateConfig===
Content-Type: text/plain; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="config"

################################################################################
# AZURE SDN CONNECTOR CONFIGURATION
# ---------------------------------
# The SDN Connector allows FortiGate to integrate with Azure:
# - Read Azure resource metadata
# - Dynamic address objects based on Azure tags
# - Automatic route table updates (for Active/Passive HA)
# - Integration with Azure services
#
# Prerequisites: The FortiGate VM must have a Managed Identity with
# appropriate Azure RBAC permissions (Reader role at minimum).
################################################################################
config system sdn-connector
	edit AzureSDN
		set type azure
	next
end

################################################################################
# GLOBAL SYSTEM SETTINGS
# ----------------------
# Basic system configuration applied at first boot.
################################################################################
config system global
    # admintimeout: Auto-logout after inactivity (minutes)
    # 120 minutes = 2 hours for lab/demo environments
    # Production: Consider shorter timeout (15-30 min) for security
    set admintimeout 120
    
    # hostname: The FortiGate's hostname
    # ${fgt_vm_name} is replaced with the actual VM name (e.g., "rw-az201-fgt-0")
    set hostname "${fgt_vm_name}"
    
    # timezone: System timezone
    # 26 = America/Toronto (EST/EDT) - common for Canada
    # Full list: FortiOS CLI "config system global" then "set timezone ?"
    set timezone 26
    
    # gui-theme: Web GUI color theme
    # Options: green, red, blue, melongene, mariner, jade, graphite, etc.
    # mariner = blue/ocean theme
    set gui-theme mariner
end

################################################################################
# SSL VPN SETTINGS
# ----------------
# Move SSL VPN to non-standard port to avoid conflicts with web GUI.
# Default HTTPS (443) is used for management; SSL VPN uses 7443.
################################################################################
config vpn ssl settings
    # port: SSL VPN listening port
    # 7443 avoids conflict with management HTTPS on 443
    set port 7443
end

################################################################################
# STATIC ROUTING
# --------------
# Routes define how FortiGate forwards traffic to different destinations.
# In Azure, the gateway is always the first IP in each subnet (.1).
################################################################################
config router static
    ############################################################################
    # ROUTE 1: Default Route (Internet)
    # ---------------------------------
    # All traffic not matching other routes goes to the external gateway.
    # This is the path to the internet via Azure's infrastructure.
    ############################################################################
    edit 1
        # gateway: Azure external subnet gateway (e.g., 10.100.1.1)
        # ${fgt_external_gw} is calculated by cidrhost(subnet, 1)
        set gateway ${fgt_external_gw}
        
        # device: Outgoing interface for this route
        # port1 = external interface
        set device port1
    next
    
    ############################################################################
    # ROUTE 2: VNet Route (Internal Networks)
    # ---------------------------------------
    # Traffic to Azure VNet addresses goes through the internal gateway.
    # This includes traffic to the protected subnet and other Azure subnets.
    ############################################################################
    edit 2
        # dst: Destination network (the entire VNet range)
        # ${vnet_network} = e.g., "10.100.0.0/16"
        set dst ${vnet_network}
        
        # gateway: Azure internal subnet gateway
        set gateway ${fgt_internal_gw}
        
        # device: Internal interface
        set device port2
    next
    
    ############################################################################
    # ROUTE 3: Azure Metadata Service
    # -------------------------------
    # Azure's instance metadata service at 168.63.129.16.
    # Used for:
    # - Load balancer health probes
    # - Azure DNS
    # - Instance metadata API
    # Must be routed through internal interface in Azure.
    ############################################################################
    edit 3
        # dst: Azure metadata IP (single host, /32)
        set dst 168.63.129.16 255.255.255.255
        set device port2
        set gateway ${fgt_internal_gw}
    next
end

################################################################################
# PROBE RESPONSE CONFIGURATION
# ----------------------------
# Configures FortiGate to respond to Azure Load Balancer health probes.
# The LB probes port 8008 to determine if FortiGate is healthy.
################################################################################
config system probe-response
    # http-probe-value: The response string for HTTP probes
    # Azure LB expects a specific response to consider the backend healthy
    set http-probe-value OK
    
    # mode: Type of probe response
    # http-probe: Respond to HTTP health checks
    set mode http-probe
end

################################################################################
# INTERFACE CONFIGURATION
# -----------------------
# Configures the FortiGate network interfaces with IP addresses and settings.
# These IPs are dynamically assigned by Azure and passed via template variables.
################################################################################
config system interface
    ############################################################################
    # PORT1: External Interface (WAN/Untrust)
    # ---------------------------------------
    # Connected to the External subnet, faces the internet via External LB.
    ############################################################################
    edit port1
        # mode: IP assignment mode
        # static: We configure the IP (from Azure NIC)
        # dhcp: FortiGate requests IP via DHCP (not recommended in Azure)
        set mode static
        
        # ip: Interface IP address and subnet mask
        # ${fgt_external_ipaddr} = dynamically assigned by Azure 
        # (e.g., 10.100.1.4)
        # ${fgt_external_mask} = subnet mask (e.g., 255.255.255.0 for /24)
        set ip ${fgt_external_ipaddr}/${fgt_external_mask}
        
        # description: Human-readable label for the interface
        set description external
        
        # allowaccess: Services allowed to access FortiGate via this interface
        # probe-response: Health probe responses (required for Azure LB)
        # ping: ICMP ping (useful for testing)
        # https: Web GUI management
        # ssh: CLI management
        # ftm: FortiToken Mobile push notifications
        set allowaccess probe-response ping https ssh ftm
    next
    
    ############################################################################
    # PORT2: Internal Interface (LAN/Trust)
    # -------------------------------------
    # Connected to the Internal subnet, faces protected resources.
    ############################################################################
    edit port2
        set mode static
        
        # ip: Internal interface IP
        # ${fgt_internal_ipaddr} = e.g., 10.100.2.4
        set ip ${fgt_internal_ipaddr}/${fgt_internal_mask}
        
        set description internal
        
        # allowaccess: Same services as external
        # In production, you might restrict this further
        set allowaccess probe-response ping https ssh ftm
    next
end

################################################################################
# FORTIFLEX LICENSE ACTIVATION
# Executes "exec vm-license" command to activate the FortiGate license.
# This command contacts FortiCare cloud to validate and apply the FortiFlex 
# token.
# Block is skipped if fgt_license_fortiflex is empty.
################################################################################

%{ if fgt_license_fortiflex != ""}
exec vm-license ${fgt_license_fortiflex}
%{ endif}
--===FortGateConfig===--