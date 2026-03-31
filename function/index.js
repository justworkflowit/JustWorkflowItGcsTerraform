const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Storage } = require('@google-cloud/storage');

const PLACEHOLDER_TOKEN = 'REPLACE_ME_WITH_JUST_WORKFLOW_IT_AUTH_TOKEN';
const API_BASE_URL = process.env.API_BASE_URL || 'https://api.justworkflowit.com';
const ORGANIZATION_ID = process.env.ORGANIZATION_ID;
const AUTH_SECRET_NAME = process.env.AUTH_SECRET_NAME;
const DEFINITION_BUCKET = process.env.DEFINITION_BUCKET;
const DEFINITION_KEYS_JSON = process.env.DEFINITION_KEYS_JSON;
const IGNORE_FAILURES = process.env.IGNORE_FAILURES === 'true';
const MAX_ATTEMPTS = parseInt(process.env.REGISTER_WORKFLOW_VERSION_MAX_ATTEMPTS || '3');
const BASE_DELAY_MS = parseInt(process.env.REGISTER_WORKFLOW_VERSION_BASE_DELAY_MS || '1000');

const secretClient = new SecretManagerServiceClient();
const storage = new Storage();

async function getAuthToken() {
  const [version] = await secretClient.accessSecretVersion({
    name: `${AUTH_SECRET_NAME}/versions/latest`,
  });
  return version.payload.data.toString('utf8');
}

async function getDefinitionFromGCS(key) {
  const [content] = await storage.bucket(DEFINITION_BUCKET).file(key).download();
  return JSON.parse(content.toString('utf8'));
}

async function apiCall(method, path, token, body) {
  const url = `${API_BASE_URL}${path}`;
  const opts = {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`API ${method} ${path} failed (${res.status}): ${JSON.stringify(data).slice(0, 500)}`);
  return data;
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function registerVersionWithRetry(token, workflowId, definition) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      return await apiCall('POST', `/organizations/${ORGANIZATION_ID}/workflows/${workflowId}/versions`, token, { definition });
      // eslint-disable-next-line no-unused-vars
    } catch (err) {
      if (attempt === MAX_ATTEMPTS) throw err;
      const delay = BASE_DELAY_MS * Math.pow(2, attempt - 1);
      console.log(`Retry ${attempt}/${MAX_ATTEMPTS} after ${delay}ms...`);
      await sleep(delay);
    }
  }
}

exports.handler = async (req, res) => {
  try {
    console.log('Starting JustWorkflowIt definition deployment...');

    const token = await getAuthToken();
    if (token === PLACEHOLDER_TOKEN) {
      console.log('Auth token is placeholder — skipping deployment. Replace the secret value to enable.');
      if (res) return res.status(200).json({ status: 'skipped', reason: 'placeholder_token' });
      return { status: 'skipped' };
    }

    const definitionKeys = JSON.parse(DEFINITION_KEYS_JSON);
    const results = [];

    // List existing workflows
    const { workflows = [] } = await apiCall('GET', `/organizations/${ORGANIZATION_ID}/workflows`, token);
    const workflowsByName = {};
    for (const wf of workflows) {
      workflowsByName[wf.name.toLowerCase()] = wf;
    }

    for (const key of definitionKeys) {
      try {
        const definition = await getDefinitionFromGCS(key);
        const workflowName = definition.workflowName;
        console.log(`Processing workflow: ${workflowName}`);

        // Create workflow if it doesn't exist
        let workflow = workflowsByName[workflowName.toLowerCase()];
        if (!workflow) {
          workflow = await apiCall('POST', `/organizations/${ORGANIZATION_ID}/workflows`, token, { name: workflowName });
          console.log(`  Created workflow: ${workflow.workflowId}`);
        }

        // Register new version
        const definitionStr = JSON.stringify(definition);
        const version = await registerVersionWithRetry(token, workflow.workflowId, definitionStr);
        console.log(`  Registered version: ${version.versionId}`);

        // Check if $LIVE tag needs updating
        let currentLive = null;
        try {
          currentLive = await apiCall('GET', `/organizations/${ORGANIZATION_ID}/workflows/${workflow.workflowId}/tags/$LIVE`, token);
          // eslint-disable-next-line no-unused-vars
        } catch (_) {
          // No $LIVE tag yet
        }

        if (!currentLive || currentLive.versionId !== version.versionId) {
          await apiCall('PUT', `/organizations/${ORGANIZATION_ID}/workflows/${workflow.workflowId}/tags/$LIVE`, token, {
            versionId: version.versionId,
          });
          console.log(`  Tagged ${version.versionId} as $LIVE`);
        } else {
          console.log(`  $LIVE tag already points to this version`);
        }

        results.push({ workflowName, status: 'success', versionId: version.versionId });
      } catch (err) {
        console.error(`  Failed: ${err.message}`);
        results.push({ key, status: 'error', error: err.message.slice(0, 500) });
        if (!IGNORE_FAILURES) throw err;
      }
    }

    console.log('Deployment complete:', JSON.stringify(results));
    if (res) return res.status(200).json({ status: 'success', results });
    return { status: 'success', results };
  } catch (err) {
    console.error('Deployment failed:', err.message);
    if (IGNORE_FAILURES) {
      if (res) return res.status(200).json({ status: 'ignored_failure', error: err.message.slice(0, 1000) });
      return { status: 'ignored_failure' };
    }
    if (res) return res.status(500).json({ status: 'error', error: err.message.slice(0, 1000) });
    throw err;
  }
};
