terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "random" {}

# -----------------------------
# RANDOM PASSWORD
# Generate one admin password for both lab VMs
# -----------------------------
resource "random_password" "vm_admin_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*-_=+?"
}

# -----------------------------
# RESOURCE GROUP
# Create a new resource group for Lab 05
# -----------------------------
resource "azurerm_resource_group" "rg5" {
  name     = "az104-rg5"
  location = "East US"
}

# -----------------------------
# 1) CoreServicesVnet
# Core network and subnets
# -----------------------------
resource "azurerm_virtual_network" "core_vnet" {
  name                = "CoreServicesVnet"
  location            = azurerm_resource_group.rg5.location
  resource_group_name = azurerm_resource_group.rg5.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "core_subnet" {
  name                 = "Core"
  resource_group_name  = azurerm_resource_group.rg5.name
  virtual_network_name = azurerm_virtual_network.core_vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "perimeter_subnet" {
  name                 = "perimeter"
  resource_group_name  = azurerm_resource_group.rg5.name
  virtual_network_name = azurerm_virtual_network.core_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# -----------------------------
# 2) ManufacturingVnet
# Manufacturing network and subnet
# -----------------------------
resource "azurerm_virtual_network" "manufacturing_vnet" {
  name                = "ManufacturingVnet"
  location            = azurerm_resource_group.rg5.location
  resource_group_name = azurerm_resource_group.rg5.name
  address_space       = ["172.16.0.0/16"]
}

resource "azurerm_subnet" "manufacturing_subnet" {
  name                 = "Manufacturing"
  resource_group_name  = azurerm_resource_group.rg5.name
  virtual_network_name = azurerm_virtual_network.manufacturing_vnet.name
  address_prefixes     = ["172.16.0.0/24"]
}

# -----------------------------
# 3) Network Interfaces
# One NIC for each VM
# No public IPs, as required by the lab
# -----------------------------
resource "azurerm_network_interface" "core_vm_nic" {
  name                = "coreservicesvm-nic"
  location            = azurerm_resource_group.rg5.location
  resource_group_name = azurerm_resource_group.rg5.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.core_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "manufacturing_vm_nic" {
  name                = "manufacturingvm-nic"
  location            = azurerm_resource_group.rg5.location
  resource_group_name = azurerm_resource_group.rg5.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.manufacturing_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# -----------------------------
# 4) Core Services VM
# -----------------------------
resource "azurerm_windows_virtual_machine" "core_vm" {
  name                = "CoreServicesVM"
  resource_group_name = azurerm_resource_group.rg5.name
  location            = azurerm_resource_group.rg5.location
  size                = "Standard_DC1s_v3"
  admin_username      = "localadmin"
  admin_password      = random_password.vm_admin_password.result
  computer_name       = "CoreServicesVM"
  patch_mode          = "AutomaticByPlatform"
  provision_vm_agent  = true

  network_interface_ids = [
    azurerm_network_interface.core_vm_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

# -----------------------------
# 5) Manufacturing VM
# -----------------------------
resource "azurerm_windows_virtual_machine" "manufacturing_vm" {
  name                = "ManufacturingVM"
  resource_group_name = azurerm_resource_group.rg5.name
  location            = azurerm_resource_group.rg5.location
  size                = "Standard_DC1s_v3"
  admin_username      = "localadmin"
  admin_password      = random_password.vm_admin_password.result
  computer_name       = "ManufacturingVM"
  patch_mode          = "AutomaticByPlatform"
  provision_vm_agent  = true

  network_interface_ids = [
    azurerm_network_interface.manufacturing_vm_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

# -----------------------------
# 6) Virtual Network Peering
# Connect CoreServicesVnet and ManufacturingVnet
# -----------------------------
resource "azurerm_virtual_network_peering" "core_to_manufacturing" {
  name                      = "CoreServicesVnet-to-ManufacturingVnet"
  resource_group_name       = azurerm_resource_group.rg5.name
  virtual_network_name      = azurerm_virtual_network.core_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.manufacturing_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "manufacturing_to_core" {
  name                      = "ManufacturingVnet-to-CoreServicesVnet"
  resource_group_name       = azurerm_resource_group.rg5.name
  virtual_network_name      = azurerm_virtual_network.manufacturing_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.core_vnet.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# -----------------------------
# 7) Route Table
# Create route table for CoreServices perimeter subnet
# -----------------------------
resource "azurerm_route_table" "core_route_table" {
  name                = "rt-CoreServices"
  location            = azurerm_resource_group.rg5.location
  resource_group_name = azurerm_resource_group.rg5.name

  bgp_route_propagation_enabled = false
}

# -----------------------------
# 8) Custom Route
# Send traffic to CoreServices network via future NVA
# -----------------------------
resource "azurerm_route" "perimeter_to_core" {
  name                   = "PerimetertoCore"
  resource_group_name    = azurerm_resource_group.rg5.name
  route_table_name       = azurerm_route_table.core_route_table.name
  address_prefix         = "10.0.0.0/16"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.0.1.7"
}

# -----------------------------
# 9) Route Table Association
# Associate route table with perimeter subnet
# -----------------------------
resource "azurerm_subnet_route_table_association" "perimeter_assoc" {
  subnet_id      = azurerm_subnet.perimeter_subnet.id
  route_table_id = azurerm_route_table.core_route_table.id
}

# -----------------------------
# OUTPUTS
# Useful values for verification
# -----------------------------
output "resource_group_name" {
  value = azurerm_resource_group.rg5.name
}

output "core_vm_private_ip" {
  value = azurerm_network_interface.core_vm_nic.private_ip_address
}

output "manufacturing_vm_private_ip" {
  value = azurerm_network_interface.manufacturing_vm_nic.private_ip_address
}

output "vm_admin_username" {
  value = "localadmin"
}

output "vm_admin_password" {
  value     = random_password.vm_admin_password.result
  sensitive = true
}
