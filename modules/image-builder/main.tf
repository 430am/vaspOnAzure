terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "Azure/azapi", version = "~> 2.0" }
  }
}
variable "resource_group_id" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name" { type = string }
variable "build_subnet_id" { type = string }
variable "container_id" { type = string }
variable "build_vm_size" {
  type    = string
  default = "Standard_D32as_v5"
}
variable "existing_identity_id" {
  type    = string
  default = null
}
variable "existing_identity_principal_id" {
  type    = string
  default = null
}
variable "existing_identity_client_id" {
  type    = string
  default = null
}
variable "configuration" { type = any }
variable "image_scripts" { type = map(string) }
variable "runtime_scripts" { type = map(string) }
variable "source_script" { type = string }

resource "azurerm_user_assigned_identity" "this" {
  count               = var.existing_identity_id == null ? 1 : 0
  name                = "${var.name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}
locals {
  identity_id      = var.existing_identity_id == null ? azurerm_user_assigned_identity.this[0].id : var.existing_identity_id
  principal_id     = var.existing_identity_id == null ? azurerm_user_assigned_identity.this[0].principal_id : var.existing_identity_principal_id
  client_id        = var.existing_identity_id == null ? azurerm_user_assigned_identity.this[0].client_id : var.existing_identity_client_id
  managed_image_id = "${var.resource_group_id}/providers/Microsoft.Compute/images/${var.name}"
  bootstrap = concat(
    ["set -eu", "umask 077", "install -d -m 700 /var/tmp/vasp-image-pipeline", "install -d -m 755 /opt/vasp-image/bin"],
    [for name, content in var.image_scripts : "printf '%s' '${base64encode(content)}' | base64 -d > /var/tmp/vasp-image-pipeline/${name}"],
    [for name, content in var.runtime_scripts : "printf '%s' '${base64encode(content)}' | base64 -d > /opt/vasp-image/bin/${name}"],
    [
      "printf '%s' '${base64encode(var.source_script)}' | base64 -d > /var/tmp/vasp-image-pipeline/prepare.py",
      "printf '%s' '${base64encode(jsonencode(merge(var.configuration, { identity_client_id = local.client_id })))}' | base64 -d > /var/tmp/vasp-image-pipeline/config.json",
      "chmod 755 /opt/vasp-image/bin/*",
      "bash /var/tmp/vasp-image-pipeline/customize.sh"
    ]
  )
}
resource "azurerm_role_assignment" "source" {
  scope                = var.container_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = local.principal_id
}
resource "azurerm_role_definition" "images" {
  name  = "${var.name}-image-publisher"
  scope = var.resource_group_id
  permissions {
    actions = [
      "Microsoft.Compute/images/read", "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/delete"
    ]
  }
  assignable_scopes = [var.resource_group_id]
}
resource "azurerm_role_assignment" "images" {
  scope              = var.resource_group_id
  role_definition_id = azurerm_role_definition.images.role_definition_resource_id
  principal_id       = local.principal_id
}
resource "azurerm_role_assignment" "network" {
  scope                = split("/subnets/", var.build_subnet_id)[0]
  role_definition_name = "Network Contributor"
  principal_id         = local.principal_id
}
resource "azapi_resource" "template" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  identity {
    type         = "UserAssigned"
    identity_ids = [local.identity_id]
  }
  body = {
    properties = {
      buildTimeoutInMinutes = 480
      source = {
        type      = "PlatformImage"
        publisher = "microsoft-dsvm"
        offer     = "ubuntu-hpc"
        sku       = "2204"
        version   = "latest"
      }
      vmProfile = {
        vmSize                 = var.build_vm_size
        osDiskSizeGB           = 256
        userAssignedIdentities = [local.identity_id]
        vnetConfig             = { subnetId = var.build_subnet_id }
      }
      customize = [{
        type = "Shell", name = "protected-vasp-build", inline = local.bootstrap
      }]
      distribute = [{
        type          = "ManagedImage"
        imageId       = local.managed_image_id
        location      = var.location
        runOutputName = "candidate"
        artifactTags  = { status = "unvalidated", pipeline = var.name }
      }]
    }
  }
  depends_on = [azurerm_role_assignment.source, azurerm_role_assignment.images, azurerm_role_assignment.network]
  lifecycle {
    precondition {
      condition = var.existing_identity_id == null || (
        var.existing_identity_principal_id != null && var.existing_identity_client_id != null
      )
      error_message = "A supplied identity requires its principal and client IDs."
    }
  }
}
output "template_id" { value = azapi_resource.template.id }
output "managed_image_id" { value = local.managed_image_id }
output "identity_id" { value = local.identity_id }
output "identity_client_id" { value = local.client_id }
