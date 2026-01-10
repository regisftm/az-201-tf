##############################################################################################################
#
#  FORTIGATE ACTIVE/ACTIVE DEPLOYMENT ON MICROSOFT AZURE
#  =====================================================
#
#  This Terraform project deploys a pair of FortiGate firewalls in an Active/Active configuration
#  behind Azure Load Balancers for high availability and horizontal scaling.
#
#  ARCHITECTURE OVERVIEW:
#  ----------------------
#  
#  [Internet]
#       |
#       v
#  [External Load Balancer (Public IP)]  <-- Distributes incoming traffic to FortiGate VMs
#       |
#       +---> [FortiGate-0] --+
#       |                     |
#       +---> [FortiGate-1] --+---> [Internal Load Balancer] ---> [Protected Subnet]
#       |                     |
#       +---> [FortiGate-N] --+     (Routes outbound traffic through FortiGates)
#
#
#  FILE STRUCTURE:
#  ---------------
#  00-main.tf              - This file (overview and documentation)
#  01-providers.tf         - Terraform and Azure provider configuration
#  02-variables.tf         - All input variables with descriptions
#  03-resource-group.tf    - Azure Resource Group
#  04-virtual-network.tf   - VNet and Subnets
#  05-route-tables.tf      - Route tables for traffic steering
#  06-security-groups.tf   - Network Security Groups and rules
#  07-external-lb.tf       - External (Public) Load Balancer
#  08-internal-lb.tf       - Internal Load Balancer
#  09-fortigate-nics.tf    - Network interfaces for FortiGate VMs
#  10-fortigate-vms.tf     - FortiGate Virtual Machines
#  11-outputs.tf           - Output values after deployment
#  customdata.tpl          - FortiGate bootstrap configuration template
#  summary.tpl             - Deployment summary template
#
#
#  DEPLOYMENT WORKFLOW:
#  --------------------
#  1. Initialize Terraform:     terraform init
#  2. Review the plan:          terraform plan
#  3. Apply the configuration:  terraform apply
#  4. Access FortiGate GUI:     https://<ELB_IP>:40030 (FortiGate-0)
#                               https://<ELB_IP>:40031 (FortiGate-1)
#  5. Destroy when done:        terraform destroy
#
#
#  IMPORTANT NOTES:
#  ----------------
#  - The FortiFlex tokens in variables.tf are examples - replace with your own
#  - Default credentials are in variables.tf - CHANGE THEM for production!
#  - State files contain sensitive data - secure them appropriately
#
##############################################################################################################