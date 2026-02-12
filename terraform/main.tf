# Generate SSH key pair only when no public key is provided (inline or path)
resource "tls_private_key" "runner" {
  count     = var.ssh_public_key == "" && var.ssh_public_key_path == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : (var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : tls_private_key.runner[0].public_key_openssh)
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    environment = var.environment
    purpose     = "github-runners"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.runner_name_prefix}-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "${var.runner_name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group - allow SSH
resource "azurerm_network_security_group" "main" {
  name                = "${var.runner_name_prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP, NIC, and VM for each runner
resource "azurerm_public_ip" "runner" {
  count               = var.runner_count
  name                = "${var.runner_name_prefix}-pip-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_network_interface" "runner" {
  count               = var.runner_count
  name                = "${var.runner_name_prefix}-nic-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = azurerm_resource_group.main.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.runner[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "runner" {
  count                     = var.runner_count
  network_interface_id      = azurerm_network_interface.runner[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "runner" {
  count                           = var.runner_count
  name                            = "${var.runner_name_prefix}-${count.index + 1}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  tags                            = azurerm_resource_group.main.tags

  network_interface_ids = [
    azurerm_network_interface.runner[count.index].id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    name                 = "${var.runner_name_prefix}-osdisk-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
