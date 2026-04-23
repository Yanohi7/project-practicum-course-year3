terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# -----------------------------
# CURRENT SUBSCRIPTION
# Automatically get subscription ID from az login
# -----------------------------
data "azurerm_client_config" "current" {}

# -----------------------------
# 1) Helpdesk Group (Entra ID)
# Create a security group that will receive permissions
# -----------------------------
resource "azuread_group" "helpdesk" {
  display_name     = "helpdesk"
  security_enabled = true
}

# -----------------------------
# 2) Management Group
# Create a management group to organize subscriptions
# -----------------------------
resource "azurerm_management_group" "mg1" {
  display_name = "az104-mg1"
  name         = "az104-mg1"
}

# -----------------------------
# 3) Attach Subscription to Management Group
# Link current subscription to the created management group
# -----------------------------
resource "azurerm_management_group_subscription_association" "current_sub" {
  management_group_id = azurerm_management_group.mg1.id
  subscription_id     = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}

# -----------------------------
# 4) Built-in Role Assignment
# Assign "Virtual Machine Contributor" role to helpdesk group
# Scope: management group
# -----------------------------
resource "azurerm_role_assignment" "vm_contributor_helpdesk" {
  scope                = azurerm_management_group.mg1.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_group.helpdesk.object_id
}

# -----------------------------
# 5) Custom RBAC Role
# Create a custom role based on Support actions
# Exclude provider registration permission
# -----------------------------
resource "azurerm_role_definition" "custom_support_request" {
  name        = "Custom Support Request"
  scope       = azurerm_management_group.mg1.id
  description = "A custom contributor role for support requests."

  permissions {
    actions = [
      "Microsoft.Support/*"
    ]

    not_actions = [
      "Microsoft.Support/register/action"
    ]
  }

  assignable_scopes = [
    azurerm_management_group.mg1.id
  ]
}

# -----------------------------
# 6) Assign Custom Role
# Assign created custom role to helpdesk group
# -----------------------------
resource "azurerm_role_assignment" "custom_support_helpdesk" {
  scope              = azurerm_management_group.mg1.id
  role_definition_id = azurerm_role_definition.custom_support_request.role_definition_resource_id
  principal_id       = azuread_group.helpdesk.object_id
}

# -----------------------------
# OUTPUTS
# Show important IDs after apply
# -----------------------------
output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "helpdesk_group_object_id" {
  value = azuread_group.helpdesk.object_id
}

output "management_group_id" {
  value = azurerm_management_group.mg1.id
}

output "custom_role_id" {
  value = azurerm_role_definition.custom_support_request.role_definition_resource_id
}
