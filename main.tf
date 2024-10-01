provider "google" {
  credentials = file("path/to/your/credentials.json")
  project     = "your-project-id"
  region      = "us-central1"
}

# Create a custom VPC
resource "google_compute_network" "custom_vpc" {
  name                    = "woovly-vpc"
  auto_create_subnetworks = false
}

# Create subnetwork for GKE and Cloud SQL
resource "google_compute_subnetwork" "custom_subnetwork" {
  name          = "woovly-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.custom_vpc.id
}

# Google Kubernetes Engine Cluster
resource "google_container_cluster" "gke_cluster" {
  name               = "woovly-cluster"
  location           = "us-central1"
  network            = google_compute_network.custom_vpc.name
  subnetwork         = google_compute_subnetwork.custom_subnetwork.name
  initial_node_count = 1

  node_pool {
    name       = "default-pool"
    node_count = 1

    node_config {
      machine_type = "n1-standard-1"
      oauth_scopes = [
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring"
      ]
    }
  }
}

# Cloud SQL instance for MySQL
resource "google_sql_database_instance" "cloud_sql" {
  name             = "woovly-sql"
  database_version = "MYSQL_5_7"
  region           = "us-central1"

  settings {
    tier = "db-f1-micro"
  }
}

# Cloud Storage Bucket for static files
resource "google_storage_bucket" "assets_bucket" {
  name                          = "woovly-assets"
  location                      = "US"
  uniform_bucket_level_access    = true
}

# Cloud Armor security policy
resource "google_compute_security_policy" "cloud_armor_policy" {
  name = "woovly-security-policy"
}

# API Gateway setup
resource "google_api_gateway_api" "api_gateway" {
  api_id  = "woovly-api"
  project = var.project
  location = "global"
}

resource "google_api_gateway_api_config" "api_config" {
  api              = google_api_gateway_api.api_gateway.api_id
  api_config_id    = "woovly-api-config"
  project          = var.project
  location         = "global"
}

resource "google_api_gateway_gateway" "gateway" {
  api_config      = google_api_gateway_api_config.api_config.id
  gateway_id      = "woovly-gateway"
  project         = var.project
  location        = "global"
}

# IAM Role binding for GKE
resource "google_project_iam_member" "gke_iam" {
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_container_cluster.gke_cluster.instance_service_account}"
}

# Secret Manager for storing secrets
resource "google_secret_manager_secret" "secret" {
  secret_id = "woovly-secret"

  replication {
    automatic = true
  }
}

# Enable required APIs
resource "google_project_service" "project_services" {
  for_each = toset([
    "container.googleapis.com",        # GKE
    "sqladmin.googleapis.com",        # Cloud SQL
    "compute.googleapis.com",         # VPC and Cloud Armor
    "secretmanager.googleapis.com",   # Secret Manager
    "storage.googleapis.com",         # Cloud Storage
    "logging.googleapis.com",         # Logging
    "monitoring.googleapis.com",      # Monitoring
    "apigateway.googleapis.com"       # API Gateway
  ])

  service = each.key
}

# Monitoring and Logging
resource "google_logging_project_sink" "log_sink" {
  name        = "woovly-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.assets_bucket.name}"
}

resource "google_monitoring_alert_policy" "alert_policy" {
  display_name = "GKE Monitoring Alert"

  conditions {
    display_name = "GKE CPU usage"
    condition_threshold {
      filter     = "metric.type=\"compute.googleapis.com/instance/cpu/usage_time\" resource.type=\"gke_cluster\""
      duration   = "60s"
      comparison = "COMPARISON_GT"
      threshold_value = 0.8

      aggregations {
        alignment_period  = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  combiner = "OR"
  enabled  = true
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.gke_cluster.endpoint
}

output "cloud_sql_connection_name" {
  value = google_sql_database_instance.cloud_sql.connection_name
}

