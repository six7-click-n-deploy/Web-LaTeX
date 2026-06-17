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

variable "latex_document" {
  description = "[CONTRACT] [FILE:application/x-tex:base64] LaTeX-Dokument (.tex), Base64-kodiert"
  type        = string
  default     = ""
}

variable "key_pair" {
  description = "[BACKEND] OpenStack Keypair Name für SSH-Zugang (optional)"
  type        = string
  default     = ""
}

############################

variable "image_name" {
  description = "@openstack:image:name"
  type        = string
  default     = "web-latex-vX"
}

variable "network_uuid" {
  description = "@openstack:network:id"
  type        = string
  default     = "34a00b87-57ce-42c4-8e1b-9ea8a657ec2e"
}

variable "floating_ip_pool" {
  description = "@openstack:floating_ip_pool:name"
  type        = string
  default     = "DHBW"
}

variable "shared_secgroup_id" {
  description = "@openstack:security_group:id"
  type        = string
  default     = "4ffaf007-df66-4250-9118-1bd99378d34a"
}