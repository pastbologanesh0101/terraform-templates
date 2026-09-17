variable "name_prefix" {
  description = "Prefix used to name the generated secret artifacts (e.g. app name)."
  type        = string
}

variable "environment" {
  description = "Deployment environment these demo secrets belong to."
  type        = string
}

variable "password_length" {
  description = "Length of the generated demo password."
  type        = number
  default     = 24
}

variable "output_dir" {
  description = "Directory where the demo secrets file will be written."
  type        = string
  default     = "./generated"
}
