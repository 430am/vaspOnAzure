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
variable "managed_image_id" { type = string }
variable "image_definition_id" { type = string }
variable "image_version" {
  type = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "An immutable numeric gallery image version is required."
  }
}
variable "location" {
  type    = string
  default = "centralus"
}
variable "replication_regions" {
  type    = set(string)
  default = ["centralus"]
}
locals { parts = split("/", var.image_definition_id) }
resource "azurerm_shared_image_version" "candidate" {
  name                = var.image_version
  resource_group_name = local.parts[4]
  gallery_name        = local.parts[8]
  image_name          = local.parts[10]
  location            = var.location
  managed_image_id    = var.managed_image_id
  exclude_from_latest = true
  tags                = { status = "candidate", validation = "pending" }
  dynamic "target_region" {
    for_each = setunion(var.replication_regions, toset([var.location]))
    content {
      name                   = target_region.value
      regional_replica_count = 1
      storage_account_type   = "Standard_LRS"
    }
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags, exclude_from_latest]
  }
}
output "image_version_id" { value = azurerm_shared_image_version.candidate.id }
