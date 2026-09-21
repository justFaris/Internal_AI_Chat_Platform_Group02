output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "admin_username" {
  value = var.admin_username
}

output "ssh_command" {
  value = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "data_disk_device" {
  description = "Stable device path of the data disk inside the VM (for the mount script)"
  value       = "/dev/disk/azure/data/by-lun/0"
}

output "resource_group" {
  value = azurerm_resource_group.rg.name
}