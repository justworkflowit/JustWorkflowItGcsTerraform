#!/usr/bin/env node

/**
 * Parity validation script — checks that the Terraform module satisfies
 * the resource contract defined by @justworkflowit/cdk-constructs.
 *
 * Usage: node scripts/validate-parity.js [aws|gcp]
 */

const fs = require('fs');
const path = require('path');

const CLOUD = process.argv[2] || 'aws';
const REPO_ROOT = path.resolve(__dirname, '..');

function readFile(relPath) {
  return fs.readFileSync(path.join(REPO_ROOT, relPath), 'utf8');
}

function main() {
  // Load contract
  const contractPath = path.join(REPO_ROOT, 'resource-contract.json');
  if (!fs.existsSync(contractPath)) {
    console.error('ERROR: resource-contract.json not found. Run scripts/pull-lambda-handler.sh to sync.');
    process.exit(1);
  }
  const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));

  const errors = [];

  // --- Validate inputs ---
  const variablesTf = readFile('variables.tf');
  for (const [name, spec] of Object.entries(contract.inputs)) {
    // Skip cloud-specific inputs for other clouds
    if (spec.cloud && spec.cloud !== CLOUD) continue;

    const tfVarName = name; // Already snake_case in contract
    if (!variablesTf.includes(`variable "${tfVarName}"`)) {
      errors.push(`Missing variable: "${tfVarName}" (${spec.description})`);
    }
  }

  // --- Validate outputs ---
  const outputsTf = readFile('outputs.tf');
  // Check that at least one output exists (output names differ per cloud)
  if (!outputsTf.includes('output "')) {
    errors.push('No outputs defined in outputs.tf');
  }

  // --- Validate resources ---
  const mainTf = readFile('main.tf');
  for (const [resourceKey, spec] of Object.entries(contract.resources)) {
    const expectedType = spec.terraform_resource_types?.[CLOUD];
    if (!expectedType) continue;

    if (!mainTf.includes(`resource "${expectedType}"`)) {
      errors.push(`Missing resource type: "${expectedType}" (${resourceKey}: ${spec.description})`);
    }
  }

  // --- Validate resource properties ---
  const resources = contract.resources;

  // Check definition_storage encryption
  if (resources.definition_storage?.properties?.encryption) {
    if (CLOUD === 'aws' && !mainTf.includes('server_side_encryption_configuration')) {
      errors.push('definition_storage: Missing S3 server-side encryption configuration');
    }
  }

  // Check definition_storage no public access
  if (resources.definition_storage?.properties?.no_public_access) {
    if (CLOUD === 'aws' && !mainTf.includes('aws_s3_bucket_public_access_block')) {
      errors.push('definition_storage: Missing S3 public access block');
    }
    if (CLOUD === 'gcp' && !mainTf.includes('uniform_bucket_level_access')) {
      errors.push('definition_storage: Missing uniform bucket level access');
    }
  }

  // Check definition_storage SSL enforcement
  if (resources.definition_storage?.properties?.enforce_ssl) {
    if (CLOUD === 'aws' && !mainTf.includes('SecureTransport')) {
      errors.push('definition_storage: Missing SSL enforcement bucket policy');
    }
  }

  // Check definition_deployer env vars
  if (resources.definition_deployer?.properties?.env_vars) {
    for (const envVar of resources.definition_deployer.properties.env_vars) {
      if (!mainTf.includes(envVar)) {
        errors.push(`definition_deployer: Missing environment variable "${envVar}"`);
      }
    }
  }

  // Check execution_role conditional permissions
  if (resources.execution_role?.properties?.conditional_permissions) {
    if (CLOUD === 'aws') {
      if (!mainTf.includes('lambda:InvokeFunction')) {
        errors.push('execution_role: Missing conditional Lambda invoke permission');
      }
      if (!mainTf.includes('sns:Publish')) {
        errors.push('execution_role: Missing conditional SNS publish permission');
      }
      if (!mainTf.includes('sqs:SendMessage')) {
        errors.push('execution_role: Missing conditional SQS send permission');
      }
    }
    if (CLOUD === 'gcp') {
      if (!mainTf.includes('cloudfunctions.invoker')) {
        errors.push('execution_role: Missing conditional Cloud Function invoker role');
      }
      if (!mainTf.includes('pubsub.publisher')) {
        errors.push('execution_role: Missing conditional Pub/Sub publisher role');
      }
    }
  }

  // --- Report ---
  if (errors.length > 0) {
    console.error(`\nParity validation FAILED (${errors.length} issues):\n`);
    for (const err of errors) {
      console.error(`  - ${err}`);
    }
    console.error('\nThe Terraform module is out of sync with the resource contract.');
    console.error('Update the module to match resource-contract.json from @justworkflowit/cdk-constructs.\n');
    process.exit(1);
  }

  console.log(`Parity validation PASSED (${CLOUD}): All contract requirements satisfied.`);
}

main();
