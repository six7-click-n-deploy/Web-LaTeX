############################
# PLATFORM-injizierte Variablen (vom Worker automatisch gesetzt)
############################

variable "users" {
  description = "Teams mit User-Emails — vom Worker injiziert. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}

variable "image_name" {
  description = "Glance-Image-Name — vom Worker zur Apply-Zeit gesetzt. @platform:internal"
  type        = string
}

############################
# CONTRACT-Variablen (vom Deployer im AppStore konfiguriert)
############################

variable "assignment_files" {
  description = "ZIP-Aufgabenstellung pro Team @openstack:file:team:zip"
  type = map(object({
    name         = string
    content_b64  = string
    content_type = string
    size         = number
  }))
  default = {}
}

############################
# BACKEND-Variablen (OpenStack-Infrastruktur)
############################

variable "network_uuid" {
  description = "UUID des internen Netzwerks @openstack:network:id"
  type        = string
  default     = "34a00b87-57ce-42c4-8e1b-9ea8a657ec2e"
}

variable "floating_ip_pool" {
  description = "Name des External Networks für Floating IPs @openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "ID der gemeinsamen Security Group @openstack:security_group:id"
  type        = string
  default     = "4ffaf007-df66-4250-9118-1bd99378d34a"
}

variable "key_pair" {
  description = "OpenStack Keypair Name für SSH-Zugang (optional) @openstack:keypair:name"
  type        = string
  default     = ""
}