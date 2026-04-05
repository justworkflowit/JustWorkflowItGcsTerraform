data "google_project" "current" {
  project_id = var.project_id
}

locals {
  name_prefix = "justworkflowit-${var.disambiguator}"

  # Generate stable keys for each workflow definition
  definition_keys = { for idx, def in var.workflow_definitions : idx => "definitions/${uuidv5("dns", "${var.disambiguator}-${idx}")}.json" }
}

# -----------------------------------------------------------------------------
# Auth Secret — stores JustWorkflowIt API token (must be populated manually)
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "auth_token" {
  project   = var.project_id
  secret_id = "justworkflowit-api-authtoken-${var.disambiguator}"

  replication {
    auto {}
  }

  labels = {
    managed-by = "justworkflowit"
  }
}

resource "google_secret_manager_secret_version" "auth_token" {
  secret      = google_secret_manager_secret.auth_token.id
  secret_data = "REPLACE_ME_WITH_JUST_WORKFLOW_IT_AUTH_TOKEN"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# -----------------------------------------------------------------------------
# GCS Bucket — storage for workflow definition JSON files
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "definitions" {
  project       = var.project_id
  name          = "${local.name_prefix}-workflow-definitions"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = "" # Uses Google-managed encryption
  }

  labels = {
    managed-by = "justworkflowit"
  }
}

# Upload each workflow definition to GCS
resource "google_storage_bucket_object" "definitions" {
  for_each = local.definition_keys

  bucket       = google_storage_bucket.definitions.name
  name         = each.value
  content      = var.workflow_definitions[tonumber(each.key)]
  content_type = "application/json"
}

# -----------------------------------------------------------------------------
# Cloud Function — deploys workflow definitions to JustWorkflowIt API
# -----------------------------------------------------------------------------

# Service account for the Cloud Function
resource "google_service_account" "deployer_function" {
  project      = var.project_id
  account_id   = "jwi-deployer-${substr(var.disambiguator, 0, 15)}"
  display_name = "JustWorkflowIt Definition Deployer (${var.disambiguator})"
}

# Grant function access to read the auth secret
resource "google_secret_manager_secret_iam_member" "deployer_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.auth_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.deployer_function.email}"
}

# Grant function access to read from definition bucket
resource "google_storage_bucket_iam_member" "deployer_bucket_read" {
  bucket = google_storage_bucket.definitions.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.deployer_function.email}"
}

# GCS bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  project       = var.project_id
  name          = "${local.name_prefix}-deployer-source"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    managed-by = "justworkflowit"
  }
}

# Archive the function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

resource "google_storage_bucket_object" "function_source" {
  bucket = google_storage_bucket.function_source.name
  name   = "function-${data.archive_file.function_source.output_md5}.zip"
  source = data.archive_file.function_source.output_path
}

resource "google_cloudfunctions2_function" "definition_deployer" {
  project  = var.project_id
  name     = "justworkflowit-deployer-${var.disambiguator}"
  location = var.region

  build_config {
    runtime     = "nodejs22"
    entry_point = "handler"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 300
    service_account_email = google_service_account.deployer_function.email

    environment_variables = {
      AUTH_SECRET_NAME     = google_secret_manager_secret.auth_token.id
      ORGANIZATION_ID      = var.organization_id
      API_BASE_URL         = var.api_base_url
      DEFINITION_BUCKET    = google_storage_bucket.definitions.name
      DEFINITION_KEYS_JSON = jsonencode(values(local.definition_keys))
      IGNORE_FAILURES      = tostring(var.ignore_deployer_failures)
      CLOUD_PROVIDER       = "gcp"
    }
  }

  labels = {
    managed-by = "justworkflowit"
  }
}

# Trigger deployment on apply
resource "terraform_data" "deploy_trigger" {
  triggers_replace = [
    google_storage_bucket_object.definitions,
    google_storage_bucket_object.function_source.name,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      gcloud functions call ${google_cloudfunctions2_function.definition_deployer.name} \
        --gen2 \
        --project=${var.project_id} \
        --region=${var.region} \
        --data='{"requestType":"Create","timestamp":"${timestamp()}"}'
    EOT

    on_failure = continue
  }

  depends_on = [
    google_storage_bucket_object.definitions,
    google_secret_manager_secret_version.auth_token,
    google_cloudfunctions2_function.definition_deployer,
  ]
}

# -----------------------------------------------------------------------------
# Execution Service Account — cross-project access for JustWorkflowIt
# -----------------------------------------------------------------------------

resource "google_service_account" "execution" {
  project      = var.project_id
  account_id   = "jwi-execution-${substr(var.disambiguator, 0, 15)}"
  display_name = "JustWorkflowIt Execution Role (${var.disambiguator})"
  description  = "Service account assumed by JustWorkflowIt to execute workflow steps in this project."
}

# Workload Identity Federation — allows JustWorkflowIt AWS backend to authenticate as GCP SA
resource "google_iam_workload_identity_pool" "justworkflowit" {
  project                   = var.project_id
  workload_identity_pool_id = "justworkflowit-${substr(var.disambiguator, 0, 15)}"
  display_name              = "JustWorkflowIt (${var.disambiguator})"
  description               = "Allows JustWorkflowIt production environment to authenticate."
}

resource "google_iam_workload_identity_pool_provider" "justworkflowit" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.justworkflowit.workload_identity_pool_id
  workload_identity_pool_provider_id = "justworkflowit-aws"
  display_name                       = "JustWorkflowIt AWS"

  aws {
    account_id = var.justworkflowit_aws_account_id
  }

  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_account" = "assertion.account"
    "attribute.external_id" = "assertion.arn"
  }

  attribute_condition = "attribute.aws_account == '${var.justworkflowit_aws_account_id}'"
}

# Allow federated identities to impersonate the execution service account
resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = google_service_account.execution.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.justworkflowit.name}/*"
  ]
}

# Conditional role: Cloud Function invoker
# Gen2 Cloud Functions are backed by Cloud Run — use roles/run.invoker on the
# Cloud Run service, not roles/cloudfunctions.invoker on the function resource.
resource "google_cloud_run_service_iam_member" "invoker" {
  for_each = toset(var.cloud_function_urls)

  project  = var.project_id
  location = var.region
  service  = each.value
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.execution.email}"
}

# Conditional role: Pub/Sub publisher
resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = toset(var.pubsub_topic_ids)

  project = var.project_id
  topic   = each.value
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.execution.email}"
}
