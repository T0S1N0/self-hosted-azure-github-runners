variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "github-runners-rg"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment tag (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "runner_count" {
  description = "Number of GitHub runner VMs to create"
  type        = number
  default     = 3
  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 10
    error_message = "Runner count must be between 1 and 10."
  }
}

variable "vm_size" {
  description = "Azure VM size for the runner instances"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username for SSH access to the VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "Inline SSH public key for VM access (e.g. from CI). If set, takes precedence over ssh_public_key_path."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file for VM access. Used when ssh_public_key is empty. If both empty, a key pair is generated."
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "runner_name_prefix" {
  description = "Prefix for runner VM and host names"
  type        = string
  default     = "runner"
}
