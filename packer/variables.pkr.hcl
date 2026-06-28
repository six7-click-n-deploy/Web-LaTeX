############################
# PLATFORM-Variablen (vom AppStore gesetzt)
############################

variable "image_name" {
  type        = string
  description = "Glance-Image-Name — vom Worker zur Build-Zeit gesetzt. @platform:internal"
  default     = "web-latex-vX"
}

variable "networks" {
  type        = list(string)
  description = "@openstack:network:id:list Build-Netzwerke"
  default     = ["4971e080-966d-485e-a161-3e2b7fefad53"]
}

variable "security_groups" {
  type        = list(string)
  description = "@openstack:security_group:id:list Build-Security-Groups"
  default     = ["4ffaf007-df66-4250-9118-1bd99378d34a"]
}