variable "network_name" {
  description = "Name for the VPC network and subnet."
  type        = string
}

variable "project" {
  description = "GCP project ID in which to create the network."
  type        = string
}

variable "region" {
  description = "GCP region for the subnetwork."
  type        = string
  default     = "us-central1"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnetwork."
  type        = string
  default     = "10.0.0.0/24"
}

variable "auto_create_subnetworks" {
  description = "When true GCP creates a subnet in every region automatically (legacy mode). Set to false for custom-mode networks."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Arbitrary key/value labels attached to the network resource."
  type        = map(string)
  default     = {}
}
