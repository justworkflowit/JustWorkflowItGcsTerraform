variable "project_id" {
  type        = string
  description = "GCP project ID where resources will be created."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region for resources."
}

variable "disambiguator" {
  type        = string
  description = "Unique identifier to differentiate multiple module instances in the same GCP project."
}

variable "organization_id" {
  type        = string
  description = "JustWorkflowIt organization ID (UUID). Used as the subject claim for Workload Identity Federation."

  validation {
    condition     = can(regex("^[a-f0-9-]{36}$", var.organization_id))
    error_message = "organization_id must be a valid UUID."
  }
}

variable "workflow_definitions" {
  type        = list(string)
  description = "List of JSON-stringified workflow definitions to deploy to JustWorkflowIt."

  validation {
    condition     = length(var.workflow_definitions) > 0
    error_message = "At least one workflow definition is required."
  }
}

variable "ignore_deployer_failures" {
  type        = bool
  default     = false
  description = "If true, Terraform apply won't fail if the definition deployer Cloud Function encounters errors registering workflows."
}

variable "cloud_function_urls" {
  type        = list(string)
  default     = []
  description = "URLs of GCP Cloud Functions that JustWorkflowIt should be able to invoke when executing workflow steps."
}

variable "pubsub_topic_ids" {
  type        = list(string)
  default     = []
  description = "Full resource IDs of GCP Pub/Sub topics that JustWorkflowIt should be able to publish to."
}

variable "api_base_url" {
  type        = string
  default     = "https://api.justworkflowit.com"
  description = "Base URL of the JustWorkflowIt API. Override for testing only."
}

variable "justworkflowit_aws_account_id" {
  type        = string
  default     = "588738588052"
  description = "AWS account ID of the JustWorkflowIt production environment (for Workload Identity Federation). Override for testing only."
}
