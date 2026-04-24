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
# RANDOM NAME (web app must be unique)
# -----------------------------
resource "random_string" "app_name" {
  length  = 8
  special = false
  upper   = false
}

# -----------------------------
# RESOURCE GROUP
# -----------------------------
resource "azurerm_resource_group" "rg9" {
  name     = "az104-rg9"
  location = "West Europe"
}

# --- APP SERVICE PLAN ---
resource "azurerm_service_plan" "plan" {
  name                = "az104-plan"
  resource_group_name = azurerm_resource_group.rg9.name
  location            = "West Europe"
  os_type             = "Linux"

  sku_name = "B1"
}

# -----------------------------
# WEB APP
# -----------------------------
resource "azurerm_linux_web_app" "app" {
  name                = "az104app${random_string.app_name.result}"
  location            = azurerm_resource_group.rg9.location
  resource_group_name = azurerm_resource_group.rg9.name
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    always_on = false
    application_stack {
      php_version = "8.2"
    }
  }
}

# -----------------------------
# DEPLOYMENT SLOT (staging)
# # -----------------------------
# resource "azurerm_linux_web_app_slot" "staging" {
#   name           = "staging"
#   app_service_id = azurerm_linux_web_app.app.id

#   site_config {
#     always_on = false
#     application_stack {
#       php_version = "8.2"
#     }
#   }
# }

# -----------------------------
# SOURCE CONTROL (GitHub)
# -----------------------------
# resource "azurerm_app_service_source_control" "staging_repo" {
#   app_id   = azurerm_linux_web_app.app.id
#   repo_url = "https://github.com/Azure-Samples/php-docs-hello-world"
#   branch   = "master"
# }

# -----------------------------
# AUTOSCALE
# -----------------------------
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "autoscale-webapp"
  resource_group_name = azurerm_resource_group.rg9.name
  location            = azurerm_resource_group.rg9.location
  target_resource_id  = azurerm_service_plan.plan.id

  profile {
    name = "default"

    capacity {
      default = 1
      minimum = 1
      maximum = 2
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan.id
        time_grain         = "PT1M"
        time_aggregation   = "Average"
        statistic          = "Average"
        time_window        = "PT10M"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.plan.id
        time_grain         = "PT1M"
        time_aggregation   = "Average"
        statistic          = "Average"
        time_window        = "PT10M"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# -----------------------------
# OUTPUT
# -----------------------------
output "web_app_url" {
  value = azurerm_linux_web_app.app.default_hostname
}
