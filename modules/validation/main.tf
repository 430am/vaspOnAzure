terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
variable "enabled" {
  type    = bool
  default = false
}
variable "resource_group_name" { type = string }
variable "location" {
  type    = string
  default = "centralus"
}
variable "name" {
  type    = string
  default = "vasp-validation"
}
variable "subnet_id" { type = string }
variable "image_version_id" { type = string }
variable "ssh_public_key" { type = string }
variable "vm_size" {
  type    = string
  default = "Standard_NC24ads_A100_v4"
  validation {
    condition = contains([
      "Standard_NC24ads_A100_v4", "Standard_NC48ads_A100_v4", "Standard_NC96ads_A100_v4",
      "Standard_NC40ads_H100_v5", "Standard_NC80adis_H100_v5"
    ], var.vm_size)
    error_message = "Choose a supported A100/H100 validation SKU."
  }
}
variable "vm_count" {
  type    = number
  default = 1
  validation {
    condition     = contains([1, 2], var.vm_count)
    error_message = "Controlled standalone validation permits one or two VMs."
  }
}
resource "azurerm_network_interface" "this" {
  count               = var.enabled ? var.vm_count : 0
  name                = "${var.name}-${count.index}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_linux_virtual_machine" "this" {
  count                 = var.enabled ? var.vm_count : 0
  name                  = "${var.name}-${count.index}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  source_image_id       = var.image_version_id
  admin_username        = "hpcvalidate"
  network_interface_ids = [azurerm_network_interface.this[count.index].id]
  admin_ssh_key {
    username   = "hpcvalidate"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  tags = { purpose = "temporary-vasp-validation", cleanup = "required" }
}
output "private_ips" { value = azurerm_network_interface.this[*].private_ip_address }
output "vm_ids" { value = azurerm_linux_virtual_machine.this[*].id }
