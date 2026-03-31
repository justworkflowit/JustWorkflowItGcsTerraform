output "execution_service_account_email" {
  value       = google_service_account.execution.email
  description = "Email of the service account that JustWorkflowIt uses to perform actions in your GCP project."
}

output "execution_service_account_id" {
  value       = google_service_account.execution.id
  description = "Full resource ID of the execution service account."
}

output "workload_identity_pool_provider" {
  value       = google_iam_workload_identity_pool_provider.justworkflowit.name
  description = "Full resource name of the Workload Identity Federation provider. Provide this to JustWorkflowIt for cross-project authentication."
}

output "auth_secret_id" {
  value       = google_secret_manager_secret.auth_token.id
  description = "ID of the Secret Manager secret. Replace the placeholder value with your JustWorkflowIt API auth token."
}

output "definition_bucket_name" {
  value       = google_storage_bucket.definitions.name
  description = "Name of the GCS bucket storing workflow definitions."
}
