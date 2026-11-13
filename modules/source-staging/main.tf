terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "account_name" { type = string }
variable "container_name" { type = string }
variable "endpoint_subnet_id" { type = string }
variable "vnet_id" { type = string }
variable "existing_storage_account_id" {
  type    = string
  default = null
}
variable "existing_private_dns_zone_id" {
  type    = string
  default = null
}
variable "existing_container" {
  type    = bool
  default = false
}
variable "create_private_endpoint" {
  type    = bool
  default = true
}
variable "key_vault_key_id" {
  type    = string
  default = null
}
variable "upload_principal_id" {
  type    = string
  default = null
}

# No trusted-service bypass: source is fetched inside the build VNet over private endpoint.
#trivy:ignore:AZU-0010
resource "azurerm_storage_account" "this" {
  count                             = var.existing_storage_account_id == null ? 1 : 0
  name                              = var.account_name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  identity { type = "SystemAssigned" }
  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
  }
  blob_properties {
    # No soft delete/versioning: retained copies of licensed archives are not hidden.
    versioning_enabled = false
  }
}
locals {
  account_id   = var.existing_storage_account_id == null ? azurerm_storage_account.this[0].id : var.existing_storage_account_id
  container_id = "${local.account_id}/blobServices/default/containers/${var.container_name}"
}
resource "azurerm_storage_container" "this" {
  count                 = var.existing_container ? 0 : 1
  name                  = var.container_name
  storage_account_id    = local.account_id
  container_access_type = "private"
}
resource "azurerm_private_dns_zone" "blob" {
  count               = var.create_private_endpoint && var.existing_private_dns_zone_id == null ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.create_private_endpoint && var.existing_private_dns_zone_id == null ? 1 : 0
  name                  = "image-factory"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = var.vnet_id
}
resource "azurerm_private_endpoint" "blob" {
  count               = var.create_private_endpoint ? 1 : 0
  name                = "${var.account_name}-blob-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.endpoint_subnet_id
  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = local.account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name = "blob"
    private_dns_zone_ids = [
      var.existing_private_dns_zone_id == null ? azurerm_private_dns_zone.blob[0].id : var.existing_private_dns_zone_id
    ]
  }
}
resource "azurerm_role_assignment" "upload" {
  count                = var.upload_principal_id == null ? 0 : 1
  scope                = local.container_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.upload_principal_id
  depends_on           = [azurerm_storage_container.this]
}
resource "azurerm_role_assignment" "cmk" {
  count                = var.key_vault_key_id != null && var.existing_storage_account_id == null ? 1 : 0
  scope                = split("/keys/", var.key_vault_key_id)[0]
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.this[0].identity[0].principal_id
}
resource "azurerm_storage_account_customer_managed_key" "this" {
  count              = var.key_vault_key_id != null && var.existing_storage_account_id == null ? 1 : 0
  storage_account_id = local.account_id
  key_vault_id       = split("/keys/", var.key_vault_key_id)[0]
  key_name           = split("/", split("/keys/", var.key_vault_key_id)[1])[0]
  depends_on         = [azurerm_role_assignment.cmk]
}
output "account_id" { value = local.account_id }
output "container_id" { value = local.container_id }
