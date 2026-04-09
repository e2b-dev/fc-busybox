terraform {
  required_version = ">= 1.5.0, < 1.6.0"
  backend "gcs" {
    prefix = "terraform/fc-busybox-github/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.6.0"
    }
    github = {
      source  = "integrations/github"
      version = "5.42.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
}

data "google_project" "gcp_project" {}

// Workload Identity Federation for GitHub Actions
resource "google_iam_workload_identity_pool" "github_actions_deployment" {
  workload_identity_pool_id = "${var.prefix}gha-fc-busybox"
  display_name              = "GHA for ${var.github_repository} FC BusyBox"
  description               = "OIDC identity pool for build FC BusyBox ${var.github_repository} via GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "gha_identity_pool_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions_deployment.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.prefix}gh-provider"
  display_name                       = "E2B GHA identity pool provider"
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }
  attribute_condition = "assertion.repository == \"${var.github_organization}/${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "fc_busybox" {
  account_id   = "${var.prefix}fc-busybox"
  display_name = "Service account for ${var.github_repository} FC BusyBox"
}

resource "google_storage_bucket_iam_member" "fc_busybox_bucket_iam" {
  bucket = var.gcs_bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.fc_busybox.email}"
}

resource "google_service_account_iam_member" "gha_service_account_wif_tokencreator_iam_member" {
  service_account_id = google_service_account.fc_busybox.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.gcp_project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions_deployment.workload_identity_pool_id}/attribute.repository/${var.github_organization}/${var.github_repository}"
}

// GitHub secrets and variables
data "google_secret_manager_secret_version" "github_token" {
  secret = "${var.prefix}github-repo-token"
}

provider "github" {
  owner = var.github_organization
  token = data.google_secret_manager_secret_version.github_token.secret_data
}

resource "github_actions_secret" "workload_identity_provider_secret" {
  repository      = var.github_repository
  secret_name     = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  plaintext_value = "projects/${data.google_project.gcp_project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions_deployment.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.gha_identity_pool_provider.workload_identity_pool_provider_id}"
}

resource "github_actions_secret" "service_account_email_secret" {
  repository      = var.github_repository
  secret_name     = "GCP_SERVICE_ACCOUNT_EMAIL"
  plaintext_value = google_service_account.fc_busybox.email
}

resource "github_actions_variable" "gcs_bucket_name" {
  repository    = var.github_repository
  value         = var.gcs_bucket_name
  variable_name = "GCP_BUCKET_NAME"
}
