############################
# PLATFORM-Variablen (vom AppStore gesetzt)
############################

variable "image_name" {
  type        = string
  description = "[PLATFORM] Name des zu erstellenden Images (z.B. online-ide-v1) @openstack:image:name"
  default     = "web-latex-vX"
}

variable "networks" {
  type        = list(string)
  description = "[PLATFORM] Netzwerk-UUIDs für Build-VM (von Platform-Admin konfiguriert) @openstack:network:name:list"
  default     = ["4971e080-966d-485e-a161-3e2b7fefad53"]
}

variable "security_groups" {
  type        = list(string)
  description = "[PLATFORM] Security Groups für Build-VM (von Platform-Admin konfiguriert) @openstack:security_group:name:list"
  default     = ["4ffaf007-df66-4250-9118-1bd99378d34a"]
}