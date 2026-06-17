############################
# CONTRACT-Variablen (vom Deployer im AppStore gesetzt)
############################

variable "users" {
  description = "[CONTRACT] Teams mit User-Emails"
  type = map(list(object({
    email = string
  })))
  default = {}
}

variable "assignment_files" {
  description = "[CONTRACT] Vom Dozenten hochgeladene Begleitmaterialien @openstack:file:all"
  type = map(object({
    name         = string
    content_b64  = string
    size         = number
    content_type = string
  }))
  default = {}
}

variable "key_pair" {
  description = "[BACKEND] OpenStack Keypair Name für SSH-Zugang (optional)"
  type        = string
  default     = ""
}

############################
# BACKEND-Variablen (vom AppStore/Platform-Team gesetzt)
############################

variable "image_name" {
  description = "[BACKEND] Name des Packer-Images aus Glance (z.B. online-ide-v1) @openstack:image:name"
  type        = string
  default     = "web-latex-vX"
}

variable "network_uuid" {
  description = "[BACKEND] UUID des internen Netzwerks (von Platform-Admin konfiguriert) @openstack:network:id"
  type        = string
  default     = "34a00b87-57ce-42c4-8e1b-9ea8a657ec2e"
}

variable "floating_ip_pool" {
  description = "[BACKEND] Name des External Networks für Floating IPs (von Platform-Admin konfiguriert) @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "[BACKEND] ID der gemeinsamen Security Group für alle VMs @openstack:security_group:id"
  type        = string
  default     = "4ffaf007-df66-4250-9118-1bd99378d34a"
}
