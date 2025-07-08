# Grant GCS permission to publish to the Pub/Sub topic
resource "google_pubsub_topic_iam_member" "pdf_processor_gcs_publisher" {
  topic  = google_pubsub_topic.pdf_processor.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-387621335821@gs-project-accounts.iam.gserviceaccount.com"
}
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Reference existing secrets oogle_cloud_run_service.pdf_processor_servi(don't store values in Terraform)
data "google_secret_manager_secret_version" "db_password" {
  secret  = "db-password"
  project = var.project_id
}

data "google_secret_manager_secret_version" "gemini_api_key" {
  secret  = "gemini-api-key"
  project = var.project_id
}

# Enable required APIs (Terraform can also enable them, good for automation)
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "aiplatform.googleapis.com" # For Vertex AI / Gemini API
  ])
  project = var.project_id
  service = each.key
  disable_on_destroy = false
}

# 1. Google Cloud Storage Bucket for Raw PDFs
resource "google_storage_bucket" "pdf_bucket" {
  name          = "${var.project_id}-financial-pdfs" # Unique bucket name
  location      = var.region # Use the region variable for UK region
  force_destroy = true # Allows bucket to be deleted even if it contains objects
  uniform_bucket_level_access = true
}

# 2. Cloud SQL (PostgreSQL) Instance
resource "google_sql_database_instance" "postgres_instance" {
  database_version = "POSTGRES_14"
  name             = "${var.project_id}-pg-instance"
  region           = var.region
  settings {
    tier = "db-f1-micro" # Smallest, lowest cost tier. Adjust as needed.
    ip_configuration {
      ipv4_enabled = true
      # You can restrict authorized networks here for production
      # authorized_networks {
      #   value = "0.0.0.0/0" # Allow all for simplicity, restrict for production
      # }
    }
    backup_configuration {
      enabled            = true
      binary_log_enabled = false
      start_time         = "03:00"
    }
    disk_autoresize = true
    disk_size       = 20 # GB
  }
  # deletion_protection_enabled is not a supported argument for this resource, so it has been removed
}

# PostgreSQL Database
resource "google_sql_database" "financial_db" {
  name     = "financial_data"
  instance = google_sql_database_instance.postgres_instance.name
  charset  = "UTF8"
}

# PostgreSQL User
resource "google_sql_user" "db_user" {
  name     = "appuser"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_password
}

# 3. VPC Access Connector for Cloud Run to Cloud SQL (Private IP)
# This allows Cloud Run to connect to Cloud SQL using private IP, which is more secure.
resource "google_vpc_access_connector" "connector" {
  name          = "${substr(var.project_id, 0, 10)}-vpc-conn"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28" # A small, unused CIDR range within your VPC
  network       = "default" # Reference the existing default VPC by name
  min_instances = 2
  max_instances = 3
}

# 4. Service Account for Cloud Run Services
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.project_id}-cloud-run-sa"
  display_name = "Service Account for Cloud Run services"
}

# Grant permissions to the service account
resource "google_project_iam_member" "cloud_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker" # Allows other services to invoke Cloud Run services
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_admin" {
  project = var.project_id
  role    = "roles/run.admin" # Allows deploying and managing Cloud Run services
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer" # Allows reading objects from GCS
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client" # Allows connecting to Cloud SQL instances
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "secret_manager_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor" # Allows accessing secrets
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}



# 5. Cloud Run Service for PDF Processing (Placeholder - actual deployment via GitHub Actions)
resource "google_cloud_run_service" "pdf_processor_service" {
  name     = "pdf-processor"
  location = var.region
  project  = var.project_id
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "0" # Scale to zero when idle
        "autoscaling.knative.dev/maxScale"         = "1" # Keep max instances low for cost
        "run.googleapis.com/cloudsql-instances" = "finance-doc-ai:europe-west2:finance-doc-ai-pg-instance"
      }
    }
    spec {
      service_account_name = google_service_account.cloud_run_sa.email
      containers {
        image = "gcr.io/${var.project_id}/pdf-processor:latest" # Placeholder image
        resources {
          limits = {
            memory = "1Gi"
          }
        }
        env {
          name  = "DB_USER"
          value = google_sql_user.db_user.name
        }
        env {
          name = "DB_NAME"
          value = google_sql_database.financial_db.name
        }
        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = data.google_secret_manager_secret_version.db_password.secret
              key  = "latest"
            }
          }
        }
        env {
          name = "INSTANCE_CONNECTION_NAME"
          value = "finance-doc-ai:europe-west2:finance-doc-ai-pg-instance"
        }
      }
      # vpc_access block removed; VPC settings are handled via annotations for v1 resource
    }
  }
  traffic {
    percent = 100
  }
  depends_on = [
    google_project_service.apis,
    google_vpc_access_connector.connector,
    google_service_account.cloud_run_sa,
    google_project_iam_member.cloud_run_admin
  ]
}

# Allow unauthenticated access to the PDF processor service (for GCS trigger)
resource "google_cloud_run_service_iam_member" "pdf_processor_invoker" {
  location = google_cloud_run_service.pdf_processor_service.location
  project  = google_cloud_run_service.pdf_processor_service.project
  service  = google_cloud_run_service.pdf_processor_service.name
  role     = "roles/run.invoker"
  member   = "allUsers" # GCS event triggers need this if not using Pub/Sub
}

# 6. Cloud Run Service for API (Placeholder - actual deployment via GitHub Actions)
resource "google_cloud_run_service" "api_service" {
  name     = "financial-api"
  location = var.region
  project  = var.project_id
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "0" # Scale to zero when idle
        "autoscaling.knative.dev/maxScale"         = "1" # Keep max instances low for cost
        "run.googleapis.com/cloudsql-instances" = "finance-doc-ai:europe-west2:finance-doc-ai-pg-instance"
      }
    }
    spec {
      service_account_name = google_service_account.cloud_run_sa.email
      containers {
        image = "gcr.io/${var.project_id}/financial-api:latest" # Placeholder image
        resources {
          limits = {
            cpu    = "1000m" # 1 CPU
            memory = "512Mi" # 512 MB memory
          }
        }
        env {
          name  = "DB_USER"
          value = google_sql_user.db_user.name
        }
        env {
          name = "DB_NAME"
          value = google_sql_database.financial_db.name
        }
        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = data.google_secret_manager_secret_version.db_password.secret
              key  = "latest"
            }
          }
        }
        env {
          name = "GEMINI_API_KEY"
          value_from {
            secret_key_ref {
              name = data.google_secret_manager_secret_version.gemini_api_key.secret
              key  = "latest"
            }
          }
        }
        env {
          name = "INSTANCE_CONNECTION_NAME"
          value = "finance-doc-ai:europe-west2:finance-doc-ai-pg-instance"
        }
      }
      # vpc_access block removed; VPC settings are handled via annotations for v1 resource
    }
  }
  traffic {
    percent = 100
  }
  depends_on = [
    google_project_service.apis,
    google_vpc_access_connector.connector,
    google_service_account.cloud_run_sa,
    google_project_iam_member.cloud_run_admin
  ]
}

resource "google_pubsub_topic" "pdf_processor" {
  name    = "pdf-processor"
  project = var.project_id
}

# Allow unauthenticated access to the API service (for frontend)
resource "google_cloud_run_service_iam_member" "api_service_invoker" {
  location = google_cloud_run_service.api_service.location
  project  = google_cloud_run_service.api_service.project
  service  = google_cloud_run_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}



resource "google_cloud_run_service_iam_member" "pdf_processor_event_invoker" {
  location = google_cloud_run_service.pdf_processor_service.location
  project  = google_cloud_run_service.pdf_processor_service.project
  service  = google_cloud_run_service.pdf_processor_service.name
  role     = "roles/run.invoker"
member   = "serviceAccount:service-387621335821@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_storage_notification" "pdf_upload_notification" {
  bucket    = google_storage_bucket.pdf_bucket.name
  payload_format = "JSON_API_V1"
  topic     = google_pubsub_topic.pdf_processor.name
  event_types = ["OBJECT_FINALIZE"] # Trigger on new object creation/upload
  depends_on = [
    google_cloud_run_service.pdf_processor_service,
    google_cloud_run_service_iam_member.pdf_processor_event_invoker
  ]
}

# 8. Google Cloud Storage Bucket for Frontend Static Assets
resource "google_storage_bucket" "frontend_bucket" {
  name          = "${var.project_id}-frontend-assets" # Unique bucket name
  location      = var.region # Or "US" for multi-region
  force_destroy = true
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # For React routing
  }
}

# Make frontend bucket publicly accessible
resource "google_storage_bucket_iam_member" "frontend_bucket_iam_member" {
  bucket = google_storage_bucket.frontend_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}