variable "subscription_id" {
  description = "Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "project_name" {
  description = "Prefix used in all resource names"
  type        = string
  default     = "openwebui"
}

variable "location" {
  description = "Azure region. Verify VM size availability first (az vm list-skus)."
  type        = string
  default     = "uaenorth"
}

variable "vm_size" {
  description = "VM size. B2ms (2 vCPU / 8 GB) is enough when using an external model API."
  type        = string
  default     = "Standard_B2ms"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH PUBLIC key injected into the VM"
  type        = string
  default     = "~/.ssh/openwebui.pub"
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach SSH (22) and web (80/443). Example: [\"203.0.113.10/32\"]"
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs must be non-empty and must not contain 0.0.0.0/0."
  }
}

variable "os_disk_size_gb" {
  type    = number
  default = 64
}

variable "data_disk_size_gb" {
  description = "Persistent disk for Open WebUI data / Docker volumes"
  type        = number
  default     = 64
}

variable "enable_auto_shutdown" {
  description = "Daily auto-shutdown to control cost"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "HHMM in Arab Standard Time (UTC+3)"
  type        = string
  default     = "2200"
}

variable "tags" {
  type    = map(string)
  default = {}
}