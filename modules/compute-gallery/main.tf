terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "gallery_name" { type = string }
variable "image_name" { type = string }
variable "existing_gallery_id" {
  type    = string
  default = null
}
variable "existing_image_definition_id" {
  type    = string
  default = null
}
resource "azurerm_shared_image_gallery" "this" {
  count               = var.existing_gallery_id == null ? 1 : 0
  name                = var.gallery_name
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Private licensed VASP compute images"
}
locals {
  gallery_id   = var.existing_gallery_id == null ? azurerm_shared_image_gallery.this[0].id : var.existing_gallery_id
  gallery_name = reverse(split("/", local.gallery_id))[0]
  gallery_rg   = split("/", local.gallery_id)[4]
}
resource "azurerm_shared_image" "this" {
  count               = var.existing_image_definition_id == null ? 1 : 0
  name                = var.image_name
  gallery_name        = local.gallery_name
  resource_group_name = local.gallery_rg
  location            = var.location
  os_type             = "Linux"
  hyper_v_generation  = "V2"
  identifier {
    publisher = "private-hpc"
    offer     = "vasp-cyclecloud"
    sku       = "ubuntu-2204"
  }
}
output "gallery_id" { value = local.gallery_id }
output "image_definition_id" {
  value = var.existing_image_definition_id == null ? azurerm_shared_image.this[0].id : var.existing_image_definition_id
}
