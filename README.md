# JustWorkflowIt GCS Terraform Module

Terraform module for integrating GCP infrastructure with the [JustWorkflowIt](https://justworkflowit.com) workflow orchestration platform.

This module creates the GCP resources needed for JustWorkflowIt to execute workflow steps in your GCP project, including Workload Identity Federation, workflow definition deployment, and permission grants.

## Usage

```hcl
module "justworkflowit" {
  source  = "justworkflowit/justworkflowit/google"
  version = "~> 1.0"

  project_id           = "my-gcp-project"
  disambiguator        = "my-app-prod"
  organization_id      = "your-org-uuid-here"
  workflow_definitions = [file("workflows/my-workflow.json")]

  # Grant JustWorkflowIt permission to invoke your Cloud Functions
  cloud_function_urls = [google_cloudfunctions2_function.my_step_handler.name]
}
```

After applying, update the Secret Manager secret with your JustWorkflowIt API auth token:

```bash
echo -n "your-api-token-here" | gcloud secrets versions add \
  justworkflowit-api-authtoken-my-app-prod \
  --data-file=-
```

## Resources Created

| Resource | Purpose |
|----------|---------|
| Secret Manager Secret | Stores your JustWorkflowIt API auth token |
| GCS Bucket | Storage for workflow definition files |
| Cloud Function (Gen2) | Deploys workflow definitions to JustWorkflowIt on `terraform apply` |
| Service Account | Execution identity for JustWorkflowIt in your project |
| Workload Identity Pool | Enables JustWorkflowIt's AWS backend to authenticate as GCP service account |

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `project_id` | string | yes | - | GCP project ID |
| `region` | string | no | `us-central1` | GCP region |
| `disambiguator` | string | yes | - | Unique identifier for this module instance |
| `organization_id` | string | yes | - | JustWorkflowIt organization ID (UUID) |
| `workflow_definitions` | list(string) | yes | - | JSON workflow definitions to deploy |
| `ignore_deployer_failures` | bool | no | `false` | Don't fail apply on definition registration errors |
| `cloud_function_urls` | list(string) | no | `[]` | Cloud Function names to grant invoker role |
| `pubsub_topic_ids` | list(string) | no | `[]` | Pub/Sub topic IDs to grant publisher role |

## Outputs

| Name | Description |
|------|-------------|
| `execution_service_account_email` | Email of the execution service account |
| `execution_service_account_id` | Full resource ID of the service account |
| `workload_identity_pool_provider` | Workload Identity provider name (provide to JustWorkflowIt) |
| `auth_secret_id` | ID of the Secret Manager secret |
| `definition_bucket_name` | Name of the GCS bucket |

## Parity with CDK Constructs

This module creates equivalent resources to the [`@justworkflowit/cdk-constructs`](https://www.npmjs.com/package/@justworkflowit/cdk-constructs) npm package. A `resource-contract.json` file defines the shared contract, and CI validates that this module stays in sync.

## License

MIT
