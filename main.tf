terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azuread" {}
provider "random" {}

# -----------------------------
# Auto-generated password
# -----------------------------
resource "random_password" "pwd" {
  length           = 12
  special          = true
  override_special = "!@#$%^&*-_=+?"
}

# -----------------------------
# 1) Internal user
# -----------------------------
resource "azuread_user" "user1" {
  user_principal_name   = "az104-user1@viktorhudaskogmail105.onmicrosoft.com"
  display_name          = "az104-user1"
  mail_nickname         = "az104-user1"
  password              = random_password.pwd.result
  force_password_change = true
  account_enabled       = true

  job_title      = "IT Lab Administrator"
  department     = "IT"
  usage_location = "US"
}

# -----------------------------
# 2) Guest user
# -----------------------------
resource "azuread_invitation" "guest1" {
  user_email_address = "aus13538@gmail.com"
  user_display_name  = "Aus13538"
  redirect_url       = "https://portal.azure.com"

  message {
    body = "Welcome to Azure and our group project"
  }
}

# -----------------------------
# 3) Group
# -----------------------------
resource "azuread_group" "it_lab_admins" {
  display_name     = "IT Lab Administrators"
  description      = "Administrators that manage the IT lab"
  security_enabled = true
}

# -----------------------------
# 4) Add user to group
# -----------------------------
resource "azuread_group_member" "member_user1" {
  group_object_id  = azuread_group.it_lab_admins.id
  member_object_id = azuread_user.user1.id
}

# -----------------------------
# 5) Add guest to group
# -----------------------------
resource "azuread_group_member" "member_guest1" {
  group_object_id  = azuread_group.it_lab_admins.id
  member_object_id = azuread_invitation.guest1.user_id
}

# -----------------------------
# Show generated password
# -----------------------------
output "generated_password" {
  value     = random_password.pwd.result
  sensitive = true
}
