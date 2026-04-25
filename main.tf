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
# -----------------------------
locals {
  location    = "West Europe"
  vm_size     = "Standard_E2_v3"
  alert_email = "viktorhudasko@gmail.com"
}

# -----------------------------
# CURRENT SUBSCRIPTION
# Used for subscription-level activity log alert
# -----------------------------
data "azurerm_client_config" "current" {}

# -----------------------------
# RANDOM PASSWORD
# -----------------------------
resource "random_password" "admin_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*-_=+?"
}

# -----------------------------
# RESOURCE GROUP
# Create resource group for Lab 11
# -----------------------------
resource "azurerm_resource_group" "rg11" {
  name     = "az104-rg11"
  location = local.location
}

# -----------------------------
# NETWORK
# One virtual network and subnet for the monitoring VM
# -----------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "az104-11-vnet"
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name
  address_space       = ["10.110.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg11.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.110.0.0/24"]
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "az104-vm0-nic"
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# -----------------------------
# TASK 1: VIRTUAL MACHINE
# Minimal VM for monitoring scenarios
# -----------------------------
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "az104-vm0"
  resource_group_name = azurerm_resource_group.rg11.name
  location            = azurerm_resource_group.rg11.location
  size                = local.vm_size
  admin_username      = "localadmin"
  admin_password      = random_password.admin_password.result
  computer_name       = "az104-vm0"

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }
}

# -----------------------------
# LOG ANALYTICS WORKSPACE
# Workspace for Azure Monitor logs
# -----------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "az104-law11"
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# -----------------------------
# AZURE MONITOR AGENT
# Installs Azure Monitor Agent on the VM
# -----------------------------
resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

# -----------------------------
# DATA COLLECTION RULE
# Collect performance counters into Log Analytics
# -----------------------------
resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "az104-dcr11"
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "loganalytics"
    }
  }

  data_sources {
    performance_counter {
      name                          = "perfCounters"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes",
        "\\LogicalDisk(_Total)\\% Free Space"
      ]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = ["loganalytics"]
  }
}

# -----------------------------
# DATA COLLECTION RULE ASSOCIATION
# Connect the VM to the DCR
# -----------------------------
resource "azurerm_monitor_data_collection_rule_association" "vm_dcr_assoc" {
  name                    = "az104-vm0-dcr-association"
  target_resource_id      = azurerm_windows_virtual_machine.vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id

  depends_on = [
    azurerm_virtual_machine_extension.ama
  ]
}

# -----------------------------
# TASK 3: ACTION GROUP
# Email notification for operations team
# -----------------------------
resource "azurerm_monitor_action_group" "ops" {
  name                = "Alert-the-operations-team"
  resource_group_name = azurerm_resource_group.rg11.name
  short_name          = "AlertOps"

  email_receiver {
    name          = "VM was deleted"
    email_address = local.alert_email
  }
}

# -----------------------------
# TASK 2: ACTIVITY LOG ALERT
# Alert when a virtual machine is deleted in the subscription
# -----------------------------
resource "azurerm_monitor_activity_log_alert" "vm_deleted" {
  name                = "VM was deleted"
  resource_group_name = azurerm_resource_group.rg11.name
  location            = azurerm_resource_group.rg11.location
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "A VM in the subscription was deleted."
  enabled             = true

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

# -----------------------------
# TASK 5: ALERT PROCESSING RULE
# Suppress notifications during planned maintenance
# -----------------------------
resource "azurerm_monitor_alert_processing_rule_suppression" "planned_maintenance" {
  name                = "Planned-Maintenance"
  resource_group_name = azurerm_resource_group.rg11.name
  scopes              = [azurerm_resource_group.rg11.id]
  description         = "Suppress notifications during planned maintenance."
  enabled             = true

  condition {
    alert_rule_name {
      operator = "Equals"
      values   = [azurerm_monitor_activity_log_alert.vm_deleted.name]
    }
  }

  schedule {
    effective_from  = "2026-04-25T22:00:00"
    effective_until = "2026-04-26T07:00:00"
    time_zone       = "FLE Standard Time"
  }
}

# -----------------------------
# OUTPUTS
# -----------------------------
output "vm_name" {
  value = azurerm_windows_virtual_machine.vm.name
}

output "vm_size" {
  value = local.vm_size
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.law.name
}

output "action_group_name" {
  value = azurerm_monitor_action_group.ops.name
}

output "alert_rule_name" {
  value = azurerm_monitor_activity_log_alert.vm_deleted.name
}

output "admin_username" {
  value = "localadmin"
}

output "admin_password" {
  value     = random_password.admin_password.result
  sensitive = true
}
