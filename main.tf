
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
  storage_use_azuread = true
}

provider "random" {}

# -----------------------------
# SETTINGS
# Common lab settings
# -----------------------------
locals {
  location = "East US"
}

# -----------------------------
# RANDOM STORAGE ACCOUNT NAME
# Storage account name must be globally unique
# -----------------------------
resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  special = false
}

# -----------------------------
# RESOURCE GROUP
# Create a new resource group for Lab 07
# -----------------------------
resource "azurerm_resource_group" "rg7" {
  name     = "az104-rg7"
  location = local.location
}

# -----------------------------
# 1) VIRTUAL NETWORK
# Network that will be allowed to access the storage account
# -----------------------------
resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1"
  location            = azurerm_resource_group.rg7.location
  resource_group_name = azurerm_resource_group.rg7.name
  address_space       = ["10.70.0.0/16"]
}

# -----------------------------
# DEFAULT SUBNET
# Enable Microsoft.Storage service endpoint
# -----------------------------
resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg7.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.70.0.0/24"]

  service_endpoints = [
    "Microsoft.Storage"
  ]
}

# -----------------------------
# 2) STORAGE ACCOUNT
# Standard, geo-redundant, read-access geo-redundant storage
# Public network access is enabled only for selected networks
# -----------------------------
resource "azurerm_storage_account" "storage" {
  name                     = "az104st${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg7.name
  location                 = azurerm_resource_group.rg7.location
  account_tier             = "Standard"
  account_replication_type = "RAGRS"

  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  shared_access_key_enabled       = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.default.id]
    ip_rules                   = ["188.163.80.201"] // My home IP adress for testing
  }

  depends_on = [
    azurerm_subnet.default
  ]
}

# -----------------------------
# 3) LIFECYCLE MANAGEMENT POLICY
# Move base blobs to cool storage after 30 days
# -----------------------------
resource "azurerm_storage_management_policy" "move_to_cool" {
  storage_account_id = azurerm_storage_account.storage.id

  rule {
    name    = "Movetocool"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }
}

# -----------------------------
# 4) BLOB CONTAINER
# Private container for secure blob storage
# -----------------------------
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# -----------------------------
# 5) IMMUTABILITY POLICY
# Time-based retention policy for 180 days
# -----------------------------
resource "azurerm_storage_container_immutability_policy" "data_retention" {
  storage_container_resource_manager_id = azurerm_storage_container.data.id
  immutability_period_in_days           = 180
  protected_append_writes_enabled       = false
  protected_append_writes_all_enabled   = false
}

# -----------------------------
# 6) SAMPLE BLOB
# Upload a small test file to securitytest folder
# -----------------------------
resource "azurerm_storage_blob" "sample_blob" {
  name                   = "securitytest/sample.txt"
  storage_account_name   = azurerm_storage_account.storage.name
  storage_container_name = azurerm_storage_container.data.name
  type                   = "Block"
  source_content         = "This is a sample file for Azure Storage lab."
  access_tier            = "Hot"

  depends_on = [
    azurerm_storage_container.data
  ]
}

# -----------------------------
# 7) FILE SHARE
# Create Azure Files share
# -----------------------------
resource "azurerm_storage_share" "share1" {
  name               = "share1"
  storage_account_id = azurerm_storage_account.storage.id
  quota              = 5
  access_tier        = "TransactionOptimized"
}

# -----------------------------
# OUTPUTS
# Show useful values after deployment
# -----------------------------
output "resource_group_name" {
  value = azurerm_resource_group.rg7.name
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "blob_container_name" {
  value = azurerm_storage_container.data.name
}

output "file_share_name" {
  value = azurerm_storage_share.share1.name
}

output "sample_blob_name" {
  value = azurerm_storage_blob.sample_blob.name
}

output "allowed_subnet_id" {
  value = azurerm_subnet.default.id
}
