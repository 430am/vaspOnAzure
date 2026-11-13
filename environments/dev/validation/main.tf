terraform {
  required_version = ">= 1.9, < 2.0"
  backend "azurerm" {}
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
variable "subscription_id" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "image_version_id" { type = string }
variable "ssh_public_key" { type = string }
variable "enabled" {
  type    = bool
  default = false
}
variable "location" {
  type    = string
  default = "centralus"
}
variable "vm_size" {
  type    = string
  default = "Standard_NC24ads_A100_v4"
}
variable "vm_count" {
  type    = number
  default = 1
}
module "validation" {
  source              = "../../../modules/validation"
  enabled             = var.enabled
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  image_version_id    = var.image_version_id
  ssh_public_key      = var.ssh_public_key
  vm_size             = var.vm_size
  vm_count            = var.vm_count
}
output "validation" {
  value = { private_ips = module.validation.private_ips, vm_ids = module.validation.vm_ids }
}
