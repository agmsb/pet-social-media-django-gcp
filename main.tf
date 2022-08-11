# Copyright 2022 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Step 1: Activate Google Cloud
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.66"
    }
  }
}

# Step 2: Set up variables
provider "google" {
  credentials = file("core/config/credential.json")
  project = var.project
  region  = var.region
}

data "google_project" "project" {
  project_id = var.project
}

variable "project" {
  type        = string
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  default     = "us-west1"
  description = "Google Cloud Region"
}

variable "service" {
  type        = string
  default     = "socialmedia"
  description = "The name of the service"
}

# Step 3: Activate service APIs
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sql-component" {
  service            = "sql-component.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sqladmin" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}


# ------------------------------------------------------------------------------
# CREATE COMPUTE NETWORKS
# ------------------------------------------------------------------------------

# Simple network, auto-creates subnetworks
resource "google_compute_network" "private_network" {
  provider = google
  name = "pet-social-media-private-network-${random_id.name.hex}"
}

resource "google_compute_global_address" "private_ip_address" {
  provider = google-beta
  project   = var.project
  name          = local.private_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.private_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider = google-beta

  network                 = google_compute_network.private_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_vpc_access_connector" "connector" {
  for_each = {"us-west1": 8, "us-central1": 9, "us-east1": 10}
  name          = "vpc-con-${each.key}"
  ip_cidr_range = "10.${each.value}.0.0/28"
  region        = each.key
  network       = google_compute_network.private_network.name
}

# Step 4: Create a custom Service Account
resource "google_service_account" "django" {
  account_id = "django"
}

# Step 5: Create the database
resource "random_string" "random" {
  length           = 4
  special          = false
}

resource "random_password" "database_password" {
  length  = 32
  special = false
}

resource "random_id" "name" {
  byte_length = 2
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "instance" {
  name             = "sql-database-private-instance-${random_id.db_name_suffix.hex}"
  database_version = "MYSQL_8_0"
  region           = var.region
  depends_on = [google_vpc_access_connector.connector, google_compute_network.private_network]
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = "true"
      private_network = google_compute_network.private_network.id
    }
  }
  deletion_protection = true
}

resource "google_sql_database" "database" {
  name     = "django"
  instance = google_sql_database_instance.instance.name
}

resource "google_sql_user" "django" {
  name     = "django"
  instance = google_sql_database_instance.instance.name
  password = random_password.database_password.result
}


# Step 6: Create the secrets
resource "google_storage_bucket" "media" {
  name     = "${var.project}-bucket"
  location = "US"
}

resource "random_password" "django_secret_key" {
  special = false
  length  = 50
}

resource "google_secret_manager_secret" "django_settings" {
  secret_id = "django_settings"

  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager]

}

# Step 7: Prepare the secrets for Django
resource "google_secret_manager_secret_version" "django_settings" {
  secret = google_secret_manager_secret.django_settings.id

  secret_data = templatefile("etc/env.tpl", {
    bucket     = google_storage_bucket.media.name
    secret_key = random_password.django_secret_key.result
    user       = google_sql_user.django
    instance   = google_sql_database_instance.instance
    database   = google_sql_database.database
  })
}

# Step 8: Expand Service Account permissions
resource "google_secret_manager_secret_iam_binding" "django_settings" {
  secret_id = google_secret_manager_secret.django_settings.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount, local.django_serviceaccount]
}

locals {
  cloudbuild_serviceaccount = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  django_serviceaccount     = "serviceAccount:${google_service_account.django.email}"
  private_network_name = "private-network-${random_id.name.hex}"
  private_ip_name      = "private-ip-${random_id.name.hex}"
}


# Step 9: Populate secrets
resource "google_secret_manager_secret" "DATABASE_PASSWORD" {
  secret_id = "DATABASE_PASSWORD"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager, google_sql_database_instance.instance]
}

resource "google_secret_manager_secret_version" "DATABASE_PASSWORD" {
  secret      = google_secret_manager_secret.DATABASE_PASSWORD.id
  secret_data = google_sql_user.django.password
}

resource "google_secret_manager_secret_iam_binding" "DATABASE_PASSWORD" {
  secret_id = google_secret_manager_secret.DATABASE_PASSWORD.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "DATABASE_NAME" {
  secret_id = "DATABASE_NAME"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager, google_sql_database_instance.instance]
}

resource "google_secret_manager_secret_version" "DATABASE_NAME" {
  secret      = google_secret_manager_secret.DATABASE_NAME.id
  secret_data = google_sql_database.database.name
}

resource "google_secret_manager_secret_iam_binding" "DATABASE_NAME" {
  secret_id = google_secret_manager_secret.DATABASE_NAME.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "DATABASE_USER" {
  secret_id = "DATABASE_USER"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager, google_sql_database_instance.instance]
}

resource "google_secret_manager_secret_version" "DATABASE_USER" {
  secret      = google_secret_manager_secret.DATABASE_USER.id
  secret_data = google_sql_user.django.name
}

resource "google_secret_manager_secret_iam_binding" "DATABASE_USER" {
  secret_id = google_secret_manager_secret.DATABASE_USER.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "DATABASE_HOST_PROD" {
  secret_id = "DATABASE_HOST_PROD"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager, google_sql_database_instance.instance]
}

resource "google_secret_manager_secret_version" "DATABASE_HOST_PROD" {
  secret      = google_secret_manager_secret.DATABASE_HOST_PROD.id
  secret_data = google_sql_database_instance.instance.private_ip_address
}

resource "google_secret_manager_secret_iam_binding" "DATABASE_HOST_PROD" {
  secret_id = google_secret_manager_secret.DATABASE_HOST_PROD.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "DATABASE_PORT_PROD" {
  secret_id = "DATABASE_PORT_PROD"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager, google_sql_database_instance.instance]
}

resource "google_secret_manager_secret_version" "DATABASE_PORT_PROD" {
  secret      = google_secret_manager_secret.DATABASE_PORT_PROD.id
  secret_data = 3306
}

resource "google_secret_manager_secret_iam_binding" "DATABASE_PORT_PROD" {
  secret_id = google_secret_manager_secret.DATABASE_PORT_PROD.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "PROJECT_ID" {
  secret_id = "PROJECT_ID"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "PROJECT_ID" {
  secret      = google_secret_manager_secret.PROJECT_ID.id
  secret_data = var.project
}

resource "google_secret_manager_secret_iam_binding" "PROJECT_ID" {
  secret_id = google_secret_manager_secret.PROJECT_ID.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "google_secret_manager_secret" "BUCKET_NAME" {
  secret_id = "BUCKET_NAME"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "BUCKET_NAME" {
  secret      = google_secret_manager_secret.BUCKET_NAME.id
  secret_data = var.project
}

resource "google_secret_manager_secret_iam_binding" "BUCKET_NAME" {
  secret_id = google_secret_manager_secret.BUCKET_NAME.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}

resource "random_password" "superuser_password" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "superuser_password" {
  secret_id = "superuser_password"
  replication {
    automatic = true
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "superuser_password" {
  secret      = google_secret_manager_secret.superuser_password.id
  secret_data = random_password.superuser_password.result
}

resource "google_secret_manager_secret_iam_binding" "superuser_password" {
  secret_id = google_secret_manager_secret.superuser_password.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [local.cloudbuild_serviceaccount]
}


# Step 10: Create Cloud Run service
data "google_cloud_run_locations" "default" { }

resource "google_cloud_run_service" "service" {
  for_each = toset([for location in data.google_cloud_run_locations.default.locations : location if can(regex("us-(?:west|central|east)1", location))])
  name                       = "${var.project}--${each.value}"
  location                   = each.value
  project                    = var.project
  autogenerate_revision_name = true
  depends_on = [google_sql_database_instance.instance]

  template {
    spec {
      service_account_name = google_service_account.django.email
      containers {
        image = "gcr.io/${var.project}/${var.service}:latest"
        env {
          name = "PROJECT_ID"
          value = var.project
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = "100"
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.instance.connection_name
        "run.googleapis.com/client-name"        = "terraform"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector[each.key].name
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Step 11: Specify Cloud Run permissions
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  for_each = toset([for location in data.google_cloud_run_locations.default.locations : location if can(regex("us-(?:west|central|east)1", location))])
  location = google_cloud_run_service.service[each.key].location
  project  = google_cloud_run_service.service[each.key].project 
  service  = google_cloud_run_service.service[each.key].name

  policy_data = data.google_iam_policy.noauth.policy_data
}


resource "google_compute_region_network_endpoint_group" "default" {
  for_each = toset([for location in data.google_cloud_run_locations.default.locations : location if can(regex("us-(?:west|central|east)1", location))])
  name                  = "${var.project}--neg--${each.key}"
  network_endpoint_type = "SERVERLESS"
  region                = google_cloud_run_service.service[each.key].location
  cloud_run { 
    service = google_cloud_run_service.service[each.key].name
  }
}

module "lb-http" {
  source            = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version           = "~> 4.5"

  project = var.project
  name    = var.project

  ssl                             = true
  managed_ssl_certificate_domains = ["petsocialmedia.dev"]
  https_redirect                  = true
  backends = {
    default = {
      description            = null
      enable_cdn             = true
      custom_request_headers = null

      log_config = {
        enable      = true
        sample_rate = 1.0
      }

      groups = [
        for neg in google_compute_region_network_endpoint_group.default:
        {
          group = neg.id
        }
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = null
        oauth2_client_secret = null
      }
      security_policy = null
    }
  }
}


# Step 12: Grant access to the database
resource "google_project_iam_binding" "service_permissions" {
  for_each = toset([
    "run.admin", "cloudsql.client"
  ])

  role    = "roles/${each.key}"
  members = [local.cloudbuild_serviceaccount, local.django_serviceaccount]

}

resource "google_service_account_iam_binding" "cloudbuild_sa" {
  service_account_id = google_service_account.django.name
  role               = "roles/iam.serviceAccountUser"

  members = [local.cloudbuild_serviceaccount]
}


# Step 14: View final output
output "sql_private_ip_address" {
  value     = google_sql_database_instance.instance.private_ip_address
}

# output "service_url" {
#   value = google_cloud_run_service.service.status[0].url
# }

output "url" {
  value = "http://${module.lb-http.external_ip}"
}

output "superuser_password" {
  value     = google_secret_manager_secret_version.superuser_password.secret_data
  sensitive = true
}
