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
# SETTINGS
# Minimal VM size to avoid quota problems
# -----------------------------
locals {
  primary_location   = "East US"
  secondary_location = "West Europe"
  vm_size            = "Standard_FX2mds_v2 "
}

# -----------------------------
# RANDOM VALUES
# -----------------------------
resource "random_password" "admin_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*-_=+?"
}

resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  special = false
}

# -----------------------------
# RESOURCE GROUPS
# -----------------------------
resource "azurerm_resource_group" "region1" {
  name     = "az104-rg-region1"
  location = local.primary_location
}

resource "azurerm_resource_group" "region2" {
  name     = "az104-rg-region2"
  location = local.secondary_location
}

# -----------------------------
# NETWORK
# Virtual network for backup test VM
# -----------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "az104-10-vnet"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name
  address_space       = ["10.100.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.region1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.100.0.0/24"]
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "az104-10-vm0-nic"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# -----------------------------
# TASK 1: VIRTUAL MACHINE
# Minimal Windows VM for backup testing
# -----------------------------
# resource "azurerm_windows_virtual_machine" "vm" {
#   name                = "az104-10-vm0"
#   resource_group_name = azurerm_resource_group.region1.name
#   location            = azurerm_resource_group.region1.location
#   size                = local.vm_size
#   admin_username      = "localadmin"
#   admin_password      = random_password.admin_password.result
#   computer_name       = "az10410vm0"

#   network_interface_ids = [
#     azurerm_network_interface.vm_nic.id
#   ]

#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "StandardSSD_LRS"
#   }

#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2022-Datacenter"
#     version   = "latest"
#   }
# }

# -----------------------------
# TASK 2: RECOVERY SERVICES VAULT
# Vault for VM backup in primary region
# -----------------------------
resource "azurerm_recovery_services_vault" "rsv_region1" {
  name                = "az104-rsv-region1"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name
  sku                 = "Standard"

  storage_mode_type   = "GeoRedundant"
  soft_delete_enabled = true
}

# -----------------------------
# TASK 3: BACKUP POLICY
# Daily backup policy
# -----------------------------
resource "azurerm_backup_policy_vm" "backup_policy" {
  name                = "az104-backup"
  resource_group_name = azurerm_resource_group.region1.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_region1.name

  timezone = "FLE Standard Time"

  backup {
    frequency = "Daily"
    time      = "00:00"
  }

  instant_restore_retention_days = 2

  retention_daily {
    count = 7
  }
}

# -----------------------------
# TASK 3: PROTECT VM
# Enable backup for az104-10-vm0
# -----------------------------
resource "azurerm_backup_protected_vm" "protected_vm" {
  resource_group_name = azurerm_resource_group.region1.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_region1.name
  #   source_vm_id        = azurerm_windows_virtual_machine.vm.id
  backup_policy_id = azurerm_backup_policy_vm.backup_policy.id
}

# -----------------------------
# TASK 4: STORAGE ACCOUNT FOR DIAGNOSTICS
# Storage account for vault logs and metrics
# -----------------------------
resource "azurerm_storage_account" "diag_storage" {
  name                     = "az104diag${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.region1.name
  location                 = azurerm_resource_group.region1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# -----------------------------
# TASK 4: DIAGNOSTIC CATEGORIES
# Get supported diagnostic categories for the vault
# -----------------------------
data "azurerm_monitor_diagnostic_categories" "rsv_categories" {
  resource_id = azurerm_recovery_services_vault.rsv_region1.id
}

# -----------------------------
# TASK 4: DIAGNOSTIC SETTINGS
# Send vault logs and metrics to storage account
# -----------------------------
resource "azurerm_monitor_diagnostic_setting" "rsv_diagnostics" {
  name               = "Logs-and-Metrics-to-storage"
  target_resource_id = azurerm_recovery_services_vault.rsv_region1.id
  storage_account_id = azurerm_storage_account.diag_storage.id

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.rsv_categories.log_category_types
    content {
      category = enabled_log.value
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# -----------------------------
# TASK 5: SECONDARY RECOVERY SERVICES VAULT
# Vault for disaster recovery scenario
# -----------------------------
resource "azurerm_recovery_services_vault" "rsv_region2" {
  name                = "az104-rsv-region2"
  location            = azurerm_resource_group.region2.location
  resource_group_name = azurerm_resource_group.region2.name
  sku                 = "Standard"

  storage_mode_type   = "GeoRedundant"
  soft_delete_enabled = true
}

# -----------------------------
# OUTPUTS
# -----------------------------
# output "vm_name" {
#   value = azurerm_windows_virtual_machine.vm.name
# }

output "vm_size" {
  value = local.vm_size
}

output "primary_vault_name" {
  value = azurerm_recovery_services_vault.rsv_region1.name
}

output "backup_policy_name" {
  value = azurerm_backup_policy_vm.backup_policy.name
}

output "diagnostic_storage_account" {
  value = azurerm_storage_account.diag_storage.name
}

output "secondary_vault_name" {
  value = azurerm_recovery_services_vault.rsv_region2.name
}

output "admin_username" {
  value = "localadmin"
}

output "admin_password" {
  value     = random_password.admin_password.result
  sensitive = true
}
