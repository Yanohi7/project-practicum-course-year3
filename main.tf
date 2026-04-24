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

# --- Task 1: Resource Group ---
resource "azurerm_resource_group" "rg8" {
  name     = "az104-rg8-tf"
  location = "eastus2"
}

# --- Task 1: Networking ---
resource "azurerm_virtual_network" "vnet" {
  name                = "vmss-vnet"
  address_space       = ["10.82.0.0/20"]
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet0"
  resource_group_name  = azurerm_resource_group.rg8.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.82.0.0/24"]
}

# --- Task 3: Network Security Group (vmss1-nsg) ---
resource "azurerm_network_security_group" "vmss_nsg" {
  name                = "vmss1-nsg"
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name

  security_rule {
    name                       = "allow-http"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# --- Task 3: Load Balancer (vmss-lb) ---
resource "azurerm_public_ip" "lb_pip" {
  name                = "vmss-lb-pip"
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "vmss_lb" {
  name                = "vmss-lb"
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "bepool" {
  loadbalancer_id = azurerm_lb.vmss_lb.id
  name            = "BackEndAddressPool"
}

# --- Task 1 & 2: Standalone VMs (az104-vm1 & vm2) ---
resource "azurerm_public_ip" "vm_pip" {
  count               = 2
  name                = "vm${count.index + 1}-pip"
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm_nic" {
  count               = 2
  name                = "vm${count.index + 1}-nic"
  location            = azurerm_resource_group.rg8.location
  resource_group_name = azurerm_resource_group.rg8.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip[count.index].id
  }
}

resource "azurerm_windows_virtual_machine" "vms" {
  count               = 2
  name                = "az104-vm${count.index + 1}"
  resource_group_name = azurerm_resource_group.rg8.name
  location            = azurerm_resource_group.rg8.location
  size                = "Standard_B1ms"
  admin_username      = "localadmin"
  admin_password      = "P@ssw0rd1234!"

  network_interface_ids = [azurerm_network_interface.vm_nic[count.index].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

# --- Task 2: Managed Data Disk for VM1 ---
resource "azurerm_managed_disk" "vm1_disk" {
  name                 = "vm1-disk1"
  location             = azurerm_resource_group.rg8.location
  resource_group_name  = azurerm_resource_group.rg8.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
}

# --- Task 2: Attach Data Disk to VM1 ---
resource "azurerm_virtual_machine_data_disk_attachment" "vm1_attach" {
  managed_disk_id    = azurerm_managed_disk.vm1_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.vms[0].id
  lun                = 0
  caching            = "ReadWrite"
}

# --- Task 3: Virtual Machine Scale Set (vmss1) ---
resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                = "vmss1"
  resource_group_name = azurerm_resource_group.rg8.name
  location            = azurerm_resource_group.rg8.location
  sku                 = "Standard_B1s"
  instances           = 2
  admin_password      = "P@ssw0rd1234!"
  admin_username      = "localadmin"
  zones               = ["1", "2"]

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bepool.id]
    }
  }

  extension {
    name                 = "network-security-group"
    publisher            = "Microsoft.Azure.Extensions"
    type                 = "NetworkWatcherAgentWindows"
    type_handler_version = "1.4"
  }
}

# --- Task 4: Autoscale Settings ---
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "autoscale-config"
  resource_group_name = azurerm_resource_group.rg8.name
  location            = azurerm_resource_group.rg8.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.vmss.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 2
      maximum = 4
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "PercentChangeCount"
        value     = "50"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "PercentChangeCount"
        value     = "20"
        cooldown  = "PT5M"
      }
    }
  }
}
