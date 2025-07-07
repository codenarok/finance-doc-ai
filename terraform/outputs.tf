output "frontend_bucket_name" {
  description = "Name of the GCS bucket for frontend assets."
  value       = google_storage_bucket.frontend_bucket.name
}

output "frontend_url" {
  description = "URL of the static website hosted on GCS."
  value       = "http://storage.googleapis.com/${google_storage_bucket.frontend_bucket.name}/index.html"
}
output "pdf_bucket_name" {
  description = "Name of the GCS bucket for PDFs."
  value       = google_storage_bucket.pdf_bucket.name
}

output "api_service_url" {
  description = "URL of the financial API Cloud Run service."
  value       = google_cloud_run_service.api_service.status[0].url
}

output "db_connection_name" {
  description = "Connection name for Cloud SQL instance (for Cloud Run)."
  value       = google_sql_database_instance.postgres_instance.connection_name
}

output "db_user" {
  description = "Database username."
  value       = google_sql_user.db_user.name
}

output "db_name" {
  description = "Database name."
  value       = google_sql_database.financial_db.name
}


