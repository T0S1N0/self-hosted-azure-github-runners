output "runner_public_ips" {
  description = "Public IP addresses of the GitHub runner VMs"
  value       = [for vm in azurerm_linux_virtual_machine.runner : vm.public_ip_address]
}

output "runner_public_ips_list" {
  description = "Public IP addresses as a list (for Ansible inventory)"
  value       = azurerm_linux_virtual_machine.runner[*].public_ip_address
}

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

# Output the generated private key only when Terraform created it (for local use; store securely)
output "generated_ssh_private_key_pem" {
  description = "Generated SSH private key (only when no ssh_public_key or ssh_public_key_path was set). Store securely."
  value       = var.ssh_public_key == "" && var.ssh_public_key_path == "" ? tls_private_key.runner[0].private_key_pem : null
  sensitive   = true
}
