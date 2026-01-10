################################################################################
#
#  DEPLOYMENT SUMMARY TEMPLATE
#  ===========================
#
#  This template generates a human-readable summary of the deployment.
#  It's rendered by Terraform's templatefile() function and displayed as output.
#
#  TEMPLATE VARIABLES:
#  -------------------
#  $${variable}              - Simple variable substitution
#  %%{ for i, item in list } - Loop with index (i) and value (item)
#  %%{ endfor }              - End of loop
#  $${list[i]}               - Access list item by index
#
#  This output is displayed after "terraform apply" completes.
#
################################################################################
#
# FortiGate Active/Active Load Balanced of standalone FortiGate VMs for 
# resilience and scale
# Terraform deployment template for Microsoft Azure
#
# The FortiGate VMs are reachable via the public IP address of the load balancer.
# Management GUI HTTPS starts on port 40030, and for SSH it starts on port 50030.
#
# BEWARE: The state files contain sensitive data like passwords and others. 
#         After the demo clean up your clouddrive directory.
#
################################################################################

Deployment location: ${location}
Username: ${username}

################################################################################
# FORTIGATE MANAGEMENT ACCESS
# ---------------------------
# Each FortiGate has its own management port via NAT rules on the External Load
# Balancer.
# Port mapping:
#   - HTTPS: 40030 + index (FortiGate-0 = 40030, FortiGate-1 = 40031, etc.)
#   - SSH:   50030 + index (FortiGate-0 = 50030, FortiGate-1 = 50031, etc.)
################################################################################
%{ for i, ip in fgt_ext_ips ~}
# FortiGate-${i} Management GUI: https://${elb_ipaddress}:${40030+i}/
%{ endfor ~}
#
%{ for i, ip in fgt_ext_ips ~}
# FortiGate-${i} SSH Access : ssh -p ${50030+i} fortiuser@${elb_ipaddress}
%{ endfor ~}

################################################################################
# LOAD BALANCER PUBLIC IP
# -----------------------
# This is the single entry point for all traffic to the FortiGate cluster.
# Both management (via NAT rules) and production traffic use this IP.
################################################################################
ELB IP: ${elb_ipaddress}

################################################################################
# FORTIGATE PRIVATE IP ADDRESSES
# ------------------------------
# These are the private IPs assigned to each FortiGate's interfaces.
# External IPs are in the External subnet (facing internet via ELB).
# Internal IPs are in the Internal subnet (facing protected resources via ILB).
################################################################################
%{ for i, ip in fgt_ext_ips ~}
FGT-${i} External IP: ${ip}
FGT-${i} Internal IP: ${fgt_int_ips[i]}
%{ endfor ~}

################################################################################
# FORTIFLEX LICENSE TOKENS
# ------------------------
# These are the FortiFlex tokens applied to each FortiGate.
# Keep track of which token was used on which FortiGate for license management.
################################################################################
%{ for i, token in fgt_license_fortiflex ~}
FGT-${i} FortiFlex Token: ${token}
%{ endfor ~}

################################################################################