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
# Create a new resource group for Lab 04
# -----------------------------
resource "azurerm_resource_group" "rg4" {
  name     = "az104-rg4"
  location = "East US"
}

# -----------------------------
# 1) CoreServicesVnet
# Main virtual network for core services
# Address space: 10.20.0.0/16
# -----------------------------
resource "azurerm_virtual_network" "core_vnet" {
  name                = "CoreServicesVnet"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "shared_services" {
  name                 = "SharedServicesSubnet"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.core_vnet.name
  address_prefixes     = ["10.20.10.0/24"]
}

resource "azurerm_subnet" "database" {
  name                 = "DatabaseSubnet"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.core_vnet.name
  address_prefixes     = ["10.20.20.0/24"]
}

# -----------------------------
# 2) ManufacturingVnet
# Virtual network for manufacturing systems
# Address space: 10.30.0.0/16
# -----------------------------
resource "azurerm_virtual_network" "manufacturing_vnet" {
  name                = "ManufacturingVnet"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
  address_space       = ["10.30.0.0/16"]
}

resource "azurerm_subnet" "sensor1" {
  name                 = "SensorSubnet1"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.manufacturing_vnet.name
  address_prefixes     = ["10.30.20.0/24"]
}

resource "azurerm_subnet" "sensor2" {
  name                 = "SensorSubnet2"
  resource_group_name  = azurerm_resource_group.rg4.name
  virtual_network_name = azurerm_virtual_network.manufacturing_vnet.name
  address_prefixes     = ["10.30.21.0/24"]
}

# -----------------------------
# 3) Application Security Group
# Group for web application resources
# -----------------------------
resource "azurerm_application_security_group" "asg_web" {
  name                = "asg-web"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
}

# -----------------------------
# 4) Network Security Group
# Security group for SharedServicesSubnet
# -----------------------------
resource "azurerm_network_security_group" "nsg_secure" {
  name                = "myNSGSecure"
  location            = azurerm_resource_group.rg4.location
  resource_group_name = azurerm_resource_group.rg4.name
}

# -----------------------------
# 5) Inbound Rule
# Allow TCP 80 and 443 from ASG
# -----------------------------
resource "azurerm_network_security_rule" "allow_asg_inbound" {
  name                                  = "AllowASG"
  priority                              = 100
  direction                             = "Inbound"
  access                                = "Allow"
  protocol                              = "Tcp"
  source_port_range                     = "*"
  destination_port_ranges               = ["80", "443"]
  source_application_security_group_ids = [azurerm_application_security_group.asg_web.id]
  destination_address_prefix            = "*"
  resource_group_name                   = azurerm_resource_group.rg4.name
  network_security_group_name           = azurerm_network_security_group.nsg_secure.name
}

# -----------------------------
# 6) Outbound Rule
# Deny Internet outbound traffic
# -----------------------------
resource "azurerm_network_security_rule" "deny_internet_outbound" {
  name                        = "DenyInternetOutbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.rg4.name
  network_security_group_name = azurerm_network_security_group.nsg_secure.name
}

# -----------------------------
# 7) NSG Association
# Associate NSG with SharedServicesSubnet
# -----------------------------
resource "azurerm_subnet_network_security_group_association" "shared_services_assoc" {
  subnet_id                 = azurerm_subnet.shared_services.id
  network_security_group_id = azurerm_network_security_group.nsg_secure.id
}

# -----------------------------
# 8) Public DNS Zone
# Public DNS zone and A record
# -----------------------------
resource "azurerm_dns_zone" "public_zone" {
  name                = "viktor-lab4-demo123.com"
  resource_group_name = azurerm_resource_group.rg4.name
}

resource "azurerm_dns_a_record" "www_record" {
  name                = "www"
  zone_name           = azurerm_dns_zone.public_zone.name
  resource_group_name = azurerm_resource_group.rg4.name
  ttl                 = 1
  records             = ["10.1.1.4"]
}

# -----------------------------
# 9) Private DNS Zone
# Private DNS zone linked to ManufacturingVnet
# -----------------------------
resource "azurerm_private_dns_zone" "private_zone" {
  name                = "private.viktor-lab4-demo123.com"
  resource_group_name = azurerm_resource_group.rg4.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "manufacturing_link" {
  name                  = "manufacturing-link"
  resource_group_name   = azurerm_resource_group.rg4.name
  private_dns_zone_name = azurerm_private_dns_zone.private_zone.name
  virtual_network_id    = azurerm_virtual_network.manufacturing_vnet.id
}

resource "azurerm_private_dns_a_record" "sensorvm_record" {
  name                = "sensorvm"
  zone_name           = azurerm_private_dns_zone.private_zone.name
  resource_group_name = azurerm_resource_group.rg4.name
  ttl                 = 1
  records             = ["10.1.1.4"]
}

# -----------------------------
# OUTPUTS
# Show important names after apply
# -----------------------------
output "resource_group_name" {
  value = azurerm_resource_group.rg4.name
}

output "core_vnet_name" {
  value = azurerm_virtual_network.core_vnet.name
}

output "manufacturing_vnet_name" {
  value = azurerm_virtual_network.manufacturing_vnet.name
}

output "public_dns_name_servers" {
  value = azurerm_dns_zone.public_zone.name_servers
}
