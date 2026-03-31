provider "google" {
  project = "my-gcp-project"
  region  = "us-central1"
}

# Example Cloud Function that JustWorkflowIt will invoke
resource "google_cloudfunctions2_function" "my_step_handler" {
  name     = "my-workflow-step-handler"
  location = "us-central1"

  build_config {
    runtime     = "nodejs22"
    entry_point = "handler"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = "function-source.zip"
      }
    }
  }

  service_config {
    available_memory = "256M"
    timeout_seconds  = 60
  }
}

resource "google_storage_bucket" "source" {
  name     = "my-step-handler-source"
  location = "US"
}

# JustWorkflowIt integration
module "justworkflowit" {
  source = "../../"

  project_id           = "my-gcp-project"
  disambiguator        = "my-app-prod"
  organization_id      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  workflow_definitions = [file("${path.module}/workflows/my-workflow.json")]
  cloud_function_urls  = [google_cloudfunctions2_function.my_step_handler.name]
}

output "execution_service_account" {
  value = module.justworkflowit.execution_service_account_email
}
