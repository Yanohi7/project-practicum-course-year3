terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------------
# RESOURCE GROUP
# Create a new resource group
# -----------------------------
resource "azurerm_resource_group" "rg3" {
  name     = "az104-rg3"
  location = "East US"
}

# -----------------------------
# DISK 1
# Initial managed disk from Task 1
# -----------------------------
resource "azurerm_managed_disk" "disk1" {
  name                 = "az104-disk1"
  location             = azurerm_resource_group.rg3.location
  resource_group_name  = azurerm_resource_group.rg3.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# -----------------------------
# DISK 2
# Redeployed disk from edited template
# -----------------------------
resource "azurerm_managed_disk" "disk2" {
  name                 = "az104-disk2"
  location             = azurerm_resource_group.rg3.location
  resource_group_name  = azurerm_resource_group.rg3.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# -----------------------------
# DISK 3
# Simulates deployment with PowerShell
# -----------------------------
resource "azurerm_managed_disk" "disk3" {
  name                 = "az104-disk3"
  location             = azurerm_resource_group.rg3.location
  resource_group_name  = azurerm_resource_group.rg3.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# -----------------------------
# DISK 4
# Simulates deployment with CLI
# -----------------------------
resource "azurerm_managed_disk" "disk4" {
  name                 = "az104-disk4"
  location             = azurerm_resource_group.rg3.location
  resource_group_name  = azurerm_resource_group.rg3.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# -----------------------------
# DISK 5
# Bicep equivalent:
# managedDiskName -> az104-disk5
# diskSizeinGiB   -> 32
# sku name        -> StandardSSD_LRS
# -----------------------------
resource "azurerm_managed_disk" "disk5" {
  name                 = "az104-disk5"
  location             = azurerm_resource_group.rg3.location
  resource_group_name  = azurerm_resource_group.rg3.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# -----------------------------
# OUTPUTS
# Show resource group and disk names after apply
# -----------------------------
output "resource_group_name" {
  value = azurerm_resource_group.rg3.name
}

output "managed_disks" {
  value = [
    azurerm_managed_disk.disk1.name,
    azurerm_managed_disk.disk2.name,
    azurerm_managed_disk.disk3.name,
    azurerm_managed_disk.disk4.name,
    azurerm_managed_disk.disk5.name
  ]
}
