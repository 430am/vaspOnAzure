terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "existing_build_subnet_id" {
  type    = string
  default = null
}
variable "existing_endpoint_subnet_id" {
  type    = string
  default = null
}
variable "address_space" {
  type    = list(string)
  default = ["10.240.0.0/16"]
}
variable "build_subnet_prefix" {
  type    = string
  default = "10.240.0.0/24"
}
variable "endpoint_subnet_prefix" {
  type    = string
  default = "10.240.1.0/24"
}

locals { create = var.existing_build_subnet_id == null }

resource "azurerm_virtual_network" "build" {
  count               = local.create ? 1 : 0
  name                = "${var.name}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
}
resource "azurerm_subnet" "build" {
  count                                         = local.create ? 1 : 0
  name                                          = "image-build"
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.build[0].name
  address_prefixes                              = [var.build_subnet_prefix]
  private_link_service_network_policies_enabled = false
}
resource "azurerm_subnet" "endpoint" {
  count                = local.create ? 1 : 0
  name                 = "private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.build[0].name
  address_prefixes     = [var.endpoint_subnet_prefix]
}
resource "azurerm_network_security_group" "build" {
  count               = local.create ? 1 : 0
  name                = "${var.name}-build-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  security_rule {
    name                       = "AIB-private-link-proxy"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "60001"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }
}
resource "azurerm_subnet_network_security_group_association" "build" {
  count                     = local.create ? 1 : 0
  subnet_id                 = azurerm_subnet.build[0].id
  network_security_group_id = azurerm_network_security_group.build[0].id
}
resource "azurerm_public_ip" "egress" {
  count               = local.create ? 1 : 0
  name                = "${var.name}-egress"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_nat_gateway" "egress" {
  count               = local.create ? 1 : 0
  name                = "${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
}
resource "azurerm_nat_gateway_public_ip_association" "egress" {
  count                = local.create ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.egress[0].id
  public_ip_address_id = azurerm_public_ip.egress[0].id
}
resource "azurerm_subnet_nat_gateway_association" "egress" {
  count          = local.create ? 1 : 0
  subnet_id      = azurerm_subnet.build[0].id
  nat_gateway_id = azurerm_nat_gateway.egress[0].id
}
output "build_subnet_id" {
  value = local.create ? azurerm_subnet.build[0].id : var.existing_build_subnet_id
}
output "endpoint_subnet_id" {
  value = local.create ? azurerm_subnet.endpoint[0].id : coalesce(var.existing_endpoint_subnet_id, var.existing_build_subnet_id)
}
output "vnet_id" {
  value = local.create ? azurerm_virtual_network.build[0].id : split("/subnets/", var.existing_build_subnet_id)[0]
}
