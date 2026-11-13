resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
}
data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}
locals {
  rg_id = var.create_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.this[0].id
  root  = "${path.module}/../../.."
  source_configuration = {
    vasp_source_storage_account_name = var.vasp_source_storage_account_name
    vasp_source_container_name       = var.vasp_source_container_name
    vasp_source_blob_name            = var.vasp_source_blob_name
    vasp_source_checksum             = var.vasp_source_checksum
    vasp_version                     = var.vasp_version
    vasp_build_profiles              = sort(tolist(var.vasp_build_profiles))
    vasp_install_prefix              = var.vasp_install_prefix
    vasp_makefile_templates          = var.vasp_makefile_templates
    nvhpc_version                    = var.nvhpc_version
    install_missing_nvhpc            = var.install_missing_nvhpc
    mpi_tcp_port_min                 = var.mpi_tcp_port_min
    mpi_tcp_port_count               = var.mpi_tcp_port_count
    pipeline_name                    = var.name
  }
}
module "network" {
  source                      = "../../../modules/network"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  name                        = var.name
  existing_build_subnet_id    = var.existing_build_subnet_id
  existing_endpoint_subnet_id = var.existing_endpoint_subnet_id
  depends_on                  = [azurerm_resource_group.this]
}
module "gallery" {
  source                       = "../../../modules/compute-gallery"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  gallery_name                 = var.gallery_name
  image_name                   = var.image_definition_name
  existing_gallery_id          = var.existing_gallery_id
  existing_image_definition_id = var.existing_image_definition_id
  depends_on                   = [azurerm_resource_group.this]
}
module "staging" {
  source                       = "../../../modules/source-staging"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  account_name                 = var.vasp_source_storage_account_name
  container_name               = var.vasp_source_container_name
  existing_storage_account_id  = var.existing_storage_account_id
  existing_container           = var.existing_source_container
  existing_private_dns_zone_id = var.existing_private_dns_zone_id
  create_private_endpoint      = var.create_source_private_endpoint
  endpoint_subnet_id           = module.network.endpoint_subnet_id
  vnet_id                      = module.network.vnet_id
  key_vault_key_id             = var.source_key_vault_key_id
  upload_principal_id          = var.source_upload_principal_id
}
module "image_builder" {
  source                         = "../../../modules/image-builder"
  resource_group_id              = local.rg_id
  resource_group_name            = var.resource_group_name
  location                       = var.location
  name                           = var.name
  build_subnet_id                = module.network.build_subnet_id
  container_id                   = module.staging.container_id
  build_vm_size                  = var.build_vm_size
  existing_identity_id           = var.existing_identity_id
  existing_identity_principal_id = var.existing_identity_principal_id
  existing_identity_client_id    = var.existing_identity_client_id
  configuration                  = local.source_configuration
  image_scripts = {
    for f in fileset("${local.root}/scripts/image", "*.sh") : f => file("${local.root}/scripts/image/${f}")
  }
  runtime_scripts = merge(
    { for f in ["mpi-task.sh", "gpu-health.sh", "image-health.sh"] : f => file("${local.root}/scripts/validation/${f}") },
    { "mpi-smoke.c" = file("${local.root}/scripts/validation/mpi-smoke.c") }
  )
  source_script = file("${local.root}/scripts/source/prepare.py")
  depends_on    = [module.staging]
}
output "pipeline" {
  value = {
    template_id         = module.image_builder.template_id
    managed_image_id    = module.image_builder.managed_image_id
    image_definition_id = module.gallery.image_definition_id
    identity_id         = module.image_builder.identity_id
    identity_client_id  = module.image_builder.identity_client_id
    source_configuration = merge(local.source_configuration, {
      vasp_local_source_directory = var.vasp_local_source_directory
      vasp_source_archive_name    = var.vasp_source_archive_name
      vasp_source_retention_mode  = var.vasp_source_retention_mode
    })
    cyclecloud = {
      enabled            = var.cyclecloud_integration_enabled
      cluster_name       = var.cyclecloud_cluster_name
      project_name       = var.cyclecloud_project_name
      scheduler_hostname = var.cyclecloud_scheduler_hostname
      compute_subnet_id  = var.cyclecloud_compute_subnet_id
      nodearray_a100     = var.cyclecloud_nodearray_name_a100
      nodearray_h100     = var.cyclecloud_nodearray_name_h100
      partition_a100     = var.slurm_partition_name_a100
      partition_h100     = var.slurm_partition_name_h100
      image_version      = var.cyclecloud_gallery_image_version
      update_mode        = var.cyclecloud_update_mode
      region             = var.location
    }
  }
}
