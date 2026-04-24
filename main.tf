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
# Common lab settings
# -----------------------------
locals {
  location = "East US"
  vm_size  = "Standard_DC1s_v3"
}

# -----------------------------
# RANDOM PASSWORD
# Generate admin password for lab VMs
# -----------------------------
resource "random_password" "vm_admin_password" {
  length           = 16
  special          = true
  override_special = "!@#$%^&*-_=+?"
}

# -----------------------------
# RESOURCE GROUP
# Create a new resource group for Lab 06
# -----------------------------
resource "azurerm_resource_group" "rg6" {
  name     = "az104-rg6"
  location = local.location
}

# -----------------------------
# 1) VIRTUAL NETWORK
# Create one virtual network for all lab resources
# -----------------------------
resource "azurerm_virtual_network" "vnet1" {
  name                = "az104-06-vnet1"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name
  address_space       = ["10.60.0.0/22"]
}

# -----------------------------
# SUBNETS FOR VMs
# Three subnets, each subnet contains one VM
# -----------------------------
resource "azurerm_subnet" "subnet0" {
  name                 = "subnet-0"
  resource_group_name  = azurerm_resource_group.rg6.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.60.0.0/24"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet-1"
  resource_group_name  = azurerm_resource_group.rg6.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.60.1.0/24"]
}

resource "azurerm_subnet" "subnet2" {
  name                 = "subnet-2"
  resource_group_name  = azurerm_resource_group.rg6.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.60.2.0/24"]
}

# -----------------------------
# APPLICATION GATEWAY SUBNET
# Application Gateway requires a dedicated subnet
# -----------------------------
resource "azurerm_subnet" "appgw_subnet" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.rg6.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.60.3.224/27"]
}

# -----------------------------
# NETWORK SECURITY GROUP
# Allow HTTP traffic to VMs
# -----------------------------
resource "azurerm_network_security_group" "nsg" {
  name                = "az104-06-nsg1"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet0_nsg" {
  subnet_id                 = azurerm_subnet.subnet0.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "subnet1_nsg" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_subnet_network_security_group_association" "subnet2_nsg" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# -----------------------------
# NETWORK INTERFACES
# Static private IPs for backend VMs
# -----------------------------
resource "azurerm_network_interface" "nic0" {
  name                = "az104-06-nic0"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet0.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.0.4"
  }
}

resource "azurerm_network_interface" "nic1" {
  name                = "az104-06-nic1"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.1.4"
  }
}

resource "azurerm_network_interface" "nic2" {
  name                = "az104-06-nic2"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.60.2.4"
  }
}

# -----------------------------
# VM CUSTOM DATA
# Install nginx and create simple web pages
# -----------------------------
locals {
  vm0_cloud_init = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
    runcmd:
      - echo "Hello World from az104-06-vm0" > /var/www/html/index.html
      - systemctl enable nginx
      - systemctl restart nginx
  EOF

  vm1_cloud_init = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
    runcmd:
      - mkdir -p /var/www/html/image
      - echo "Hello World from az104-06-vm1" > /var/www/html/index.html
      - echo "Image server: az104-06-vm1" > /var/www/html/image/index.html
      - systemctl enable nginx
      - systemctl restart nginx
  EOF

  vm2_cloud_init = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
    runcmd:
      - mkdir -p /var/www/html/video
      - echo "Hello World from az104-06-vm2" > /var/www/html/index.html
      - echo "Video server: az104-06-vm2" > /var/www/html/video/index.html
      - systemctl enable nginx
      - systemctl restart nginx
  EOF
}

# -----------------------------
# 2) VIRTUAL MACHINES
# Three backend VMs with nginx web server
# -----------------------------
resource "azurerm_linux_virtual_machine" "vm0" {
  name                            = "az104-06-vm0"
  resource_group_name             = azurerm_resource_group.rg6.name
  location                        = azurerm_resource_group.rg6.location
  size                            = local.vm_size
  admin_username                  = "localadmin"
  admin_password                  = random_password.vm_admin_password.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic0.id
  ]

  custom_data = base64encode(local.vm0_cloud_init)

  os_disk {
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

resource "azurerm_linux_virtual_machine" "vm1" {
  name                            = "az104-06-vm1"
  resource_group_name             = azurerm_resource_group.rg6.name
  location                        = azurerm_resource_group.rg6.location
  size                            = local.vm_size
  admin_username                  = "localadmin"
  admin_password                  = random_password.vm_admin_password.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic1.id
  ]

  custom_data = base64encode(local.vm1_cloud_init)

  os_disk {
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

resource "azurerm_linux_virtual_machine" "vm2" {
  name                            = "az104-06-vm2"
  resource_group_name             = azurerm_resource_group.rg6.name
  location                        = azurerm_resource_group.rg6.location
  size                            = local.vm_size
  admin_username                  = "localadmin"
  admin_password                  = random_password.vm_admin_password.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic2.id
  ]

  custom_data = base64encode(local.vm2_cloud_init)

  os_disk {
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

# -----------------------------
# 3) LOAD BALANCER PUBLIC IP
# Static public IP for Azure Load Balancer
# -----------------------------
resource "azurerm_public_ip" "lb_pip" {
  name                = "az104-lbpip"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -----------------------------
# 4) LOAD BALANCER
# Public Standard Load Balancer
# -----------------------------
resource "azurerm_lb" "lb" {
  name                = "az104-lb"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "az104-fe"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# -----------------------------
# 5) LOAD BALANCER BACKEND POOL
# Backend pool for vm0 and vm1
# -----------------------------
resource "azurerm_lb_backend_address_pool" "lb_backend" {
  name            = "az104-be"
  loadbalancer_id = azurerm_lb.lb.id
}

resource "azurerm_network_interface_backend_address_pool_association" "vm0_lb_assoc" {
  network_interface_id    = azurerm_network_interface.nic0.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_backend.id
}

resource "azurerm_network_interface_backend_address_pool_association" "vm1_lb_assoc" {
  network_interface_id    = azurerm_network_interface.nic1.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_backend.id
}

# -----------------------------
# 6) LOAD BALANCER HEALTH PROBE
# Probe backend VMs on TCP port 80
# -----------------------------
resource "azurerm_lb_probe" "lb_probe" {
  name                = "az104-hp"
  loadbalancer_id     = azurerm_lb.lb.id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
}

# -----------------------------
# 7) LOAD BALANCER RULE
# Distribute HTTP traffic across vm0 and vm1
# -----------------------------
resource "azurerm_lb_rule" "lb_rule" {
  name                           = "az104-lbrule"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "az104-fe"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb_backend.id]
  probe_id                       = azurerm_lb_probe.lb_probe.id
  idle_timeout_in_minutes        = 4
}

# -----------------------------
# 8) APPLICATION GATEWAY PUBLIC IP
# Public IP for Application Gateway
# -----------------------------
resource "azurerm_public_ip" "appgw_pip" {
  name                = "az104-gwpip"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -----------------------------
# 9) APPLICATION GATEWAY
# Layer 7 routing for /image/* and /video/*
# -----------------------------
resource "azurerm_application_gateway" "appgw" {
  name                = "az104-appgw"
  location            = azurerm_resource_group.rg6.location
  resource_group_name = azurerm_resource_group.rg6.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "az104-gw-ipconfig"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  frontend_port {
    name = "az104-feport"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "az104-gwfe"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name         = "az104-appgwbe"
    ip_addresses = ["10.60.1.4", "10.60.2.4"]
  }

  backend_address_pool {
    name         = "az104-imagebe"
    ip_addresses = ["10.60.1.4"]
  }

  backend_address_pool {
    name         = "az104-videobe"
    ip_addresses = ["10.60.2.4"]
  }

  backend_http_settings {
    name                  = "az104-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "az104-listener"
    frontend_ip_configuration_name = "az104-gwfe"
    frontend_port_name             = "az104-feport"
    protocol                       = "Http"
  }

  url_path_map {
    name                               = "az104-pathmap"
    default_backend_address_pool_name  = "az104-appgwbe"
    default_backend_http_settings_name = "az104-http"

    path_rule {
      name                       = "images"
      paths                      = ["/image/*"]
      backend_address_pool_name  = "az104-imagebe"
      backend_http_settings_name = "az104-http"
    }

    path_rule {
      name                       = "videos"
      paths                      = ["/video/*"]
      backend_address_pool_name  = "az104-videobe"
      backend_http_settings_name = "az104-http"
    }
  }

  request_routing_rule {
    name               = "az104-gwrule"
    priority           = 10
    rule_type          = "PathBasedRouting"
    http_listener_name = "az104-listener"
    url_path_map_name  = "az104-pathmap"
  }

  depends_on = [
    azurerm_linux_virtual_machine.vm1,
    azurerm_linux_virtual_machine.vm2
  ]
}

# -----------------------------
# OUTPUTS
# Show public IPs and credentials
# -----------------------------
output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb_pip.ip_address
}

output "application_gateway_public_ip" {
  value = azurerm_public_ip.appgw_pip.ip_address
}

output "vm_admin_username" {
  value = "localadmin"
}

output "vm_admin_password" {
  value     = random_password.vm_admin_password.result
  sensitive = true
}

output "test_load_balancer_url" {
  value = "http://${azurerm_public_ip.lb_pip.ip_address}"
}

output "test_application_gateway_image_url" {
  value = "http://${azurerm_public_ip.appgw_pip.ip_address}/image/"
}

output "test_application_gateway_video_url" {
  value = "http://${azurerm_public_ip.appgw_pip.ip_address}/video/"
}
