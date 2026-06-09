############################
# PLATFORM-Variablen (vom AppStore gesetzt)
############################

variable "image_name" {
  type        = string
  description = "@openstack:image:name"
  default     = "web-latex-vX"
}

variable "networks" {
  type        = list(string)
  description = "@openstack:network:id:list"
  default     = ["4971e080-966d-485e-a161-3e2b7fefad53"]
}

variable "security_groups" {
  type        = list(string)
  description = "@openstack:security_group:id:list"
  default     = ["4ffaf007-df66-4250-9118-1bd99378d34a"]
}