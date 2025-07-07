variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources."
  type        = string
  default     = "europe-west2" 
}

variable "db_password" {
  description = "Password for the PostgreSQL database user."
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "API Key for Google Gemini."
  type        = string
  sensitive   = true
}