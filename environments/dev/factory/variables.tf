variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "centralus"
}
variable "name" {
  type    = string
  default = "vasp-dev-001"
}
variable "resource_group_name" { type = string }
variable "create_resource_group" {
  type    = bool
  default = true
}
variable "existing_build_subnet_id" {
  type    = string
  default = null
}
variable "existing_endpoint_subnet_id" {
  type    = string
  default = null
}
variable "existing_gallery_id" {
  type    = string
  default = null
}
variable "existing_image_definition_id" {
  type    = string
  default = null
}
variable "gallery_name" {
  type    = string
  default = "vasp_private"
}
variable "image_definition_name" {
  type    = string
  default = "vasp-ubuntu-hpc-2204"
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
variable "existing_storage_account_id" {
  type    = string
  default = null
}
variable "existing_source_container" {
  type    = bool
  default = false
}
variable "existing_private_dns_zone_id" {
  type    = string
  default = null
}
variable "create_source_private_endpoint" {
  type    = bool
  default = true
}
variable "source_key_vault_key_id" {
  description = "ARM key resource ID /subscriptions/.../vaults/.../keys/name; not an HTTPS key URI. BYO accounts own their CMK policy."
  type        = string
  default     = null
  validation {
    condition     = var.source_key_vault_key_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+/keys/[^/]+", var.source_key_vault_key_id))
    error_message = "CMK input must be a Key Vault ARM key resource ID."
  }
}
variable "source_upload_principal_id" {
  type    = string
  default = null
}
variable "build_vm_size" {
  type    = string
  default = "Standard_D32as_v5"
}
variable "vasp_local_source_directory" {
  description = "Operator preparation only; never passed to AIB."
  type        = string
  default     = "./source/vasp"
}
variable "vasp_source_archive_name" {
  type    = string
  default = "vasp-source.tar.gz"
  validation {
    condition     = can(regex("^[A-Za-z0-9_-][A-Za-z0-9._-]+$", var.vasp_source_archive_name)) && !strcontains(var.vasp_source_archive_name, "..")
    error_message = "Use a plain archive filename, not a local path or URL."
  }
}
variable "vasp_source_checksum" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.vasp_source_checksum))
    error_message = "Supply the approved deterministic archive SHA-256 checksum."
  }
}
variable "vasp_source_storage_account_name" { type = string }
variable "vasp_source_container_name" {
  type    = string
  default = "licensed-build-input"
}
variable "vasp_source_blob_name" {
  type    = string
  default = "vasp-source.tar.gz"
  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.vasp_source_blob_name)) && !strcontains(var.vasp_source_blob_name, "..")
    error_message = "Use an opaque safe blob name without query strings or parent segments."
  }
}
variable "vasp_source_retention_mode" {
  type    = string
  default = "delete"
  validation {
    condition     = contains(["delete", "retain"], var.vasp_source_retention_mode)
    error_message = "Retention is explicitly delete or retain; cleanup is a separate approved operation."
  }
}
variable "vasp_version" {
  type    = string
  default = "6.4.3"
  validation {
    condition     = can(regex("^6\\.[0-9]+\\.[0-9]+$", var.vasp_version))
    error_message = "This implementation supports VASP 6; supply a numeric version."
  }
}
variable "vasp_build_profiles" {
  type    = set(string)
  default = ["a100_gpu"]
  validation {
    condition = length(var.vasp_build_profiles) > 0 && alltrue([
      for p in var.vasp_build_profiles : contains(["cpu_mpi", "a100_gpu", "h100_gpu"], p)
    ])
    error_message = "Select one or more cpu_mpi, a100_gpu, h100_gpu profiles."
  }
}
variable "vasp_install_prefix" {
  type    = string
  default = "/opt/vasp"
  validation {
    condition     = can(regex("^/opt/[A-Za-z0-9_/-]+$", var.vasp_install_prefix)) && !strcontains(var.vasp_install_prefix, "..")
    error_message = "Use a dedicated /opt path without parent segments."
  }
}
variable "vasp_makefile_templates" {
  description = "Relative paths in the staged source. Empty means use the bundled nvhpc templates."
  type        = map(string)
  default     = {}
}
variable "nvhpc_version" {
  type    = string
  default = "24.3"
}
variable "install_missing_nvhpc" {
  type    = bool
  default = true
}
variable "mpi_tcp_port_min" {
  type    = number
  default = 20000
  validation {
    condition     = var.mpi_tcp_port_min == floor(var.mpi_tcp_port_min) && var.mpi_tcp_port_min >= 1024 && var.mpi_tcp_port_min <= 65535
    error_message = "TCP port minimum must be an integer in 1024..65535."
  }
}
variable "mpi_tcp_port_count" {
  type    = number
  default = 1024
  validation {
    condition     = var.mpi_tcp_port_count == floor(var.mpi_tcp_port_count) && var.mpi_tcp_port_count > 0 && var.mpi_tcp_port_min + var.mpi_tcp_port_count - 1 <= 65535
    error_message = "TCP port count must be a positive integer and keep the interval within 65535."
  }
}
variable "cyclecloud_integration_enabled" {
  type    = bool
  default = false
  validation {
    condition     = !var.cyclecloud_integration_enabled || var.cyclecloud_compute_subnet_id != null
    error_message = "Supply the existing compute subnet for CycleCloud integration."
  }
}
variable "cyclecloud_cluster_name" {
  type    = string
  default = ""
}
variable "cyclecloud_project_name" {
  type    = string
  default = "vasp-image"
}
variable "cyclecloud_scheduler_hostname" {
  type    = string
  default = ""
}
variable "cyclecloud_compute_subnet_id" {
  type    = string
  default = null
}
variable "cyclecloud_nodearray_name_a100" {
  type    = string
  default = "vasp-a100"
}
variable "cyclecloud_nodearray_name_h100" {
  type    = string
  default = "vasp-h100"
}
variable "slurm_partition_name_a100" {
  type    = string
  default = "vasp-a100"
}
variable "slurm_partition_name_h100" {
  type    = string
  default = "vasp-h100"
}
variable "cyclecloud_gallery_image_version" {
  type    = string
  default = "1.0.0"
}
variable "cyclecloud_update_mode" {
  type    = string
  default = "plan-only"
  validation {
    condition     = var.cyclecloud_update_mode == "plan-only"
    error_message = "Terraform does not own the existing cluster. Apply reviewed changes with CycleCloud CLI."
  }
}
