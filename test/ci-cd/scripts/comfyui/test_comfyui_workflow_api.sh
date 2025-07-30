#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# Define variables for clarity and ease of maintenance
ACP_REPO_DIR=${ACP_REPO_DIR}
WORKFLOW_DIR="${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api"
HOSTNAME="workflow-api.comfyui.inf-dev.endpoints.comfyui-ab8.cloud.goog"
SERVICE_ACCOUNT_EMAIL="inf-dev-workflow-api@comfyui-ab8.iam.gserviceaccount.com"

# Change to the correct directory
cd "${WORKFLOW_DIR}"

# Function to create and sign a JWT token for a given audience path
create_jwt() {
  local audience_path=$1
  local output_file=$2

  cat > jwt-claim.json << EOF
{
  "iss": "${SERVICE_ACCOUNT_EMAIL}",
  "sub": "${SERVICE_ACCOUNT_EMAIL}",
  "aud": "https://${HOSTNAME}${audience_path}",
  "iat": $(date +%s),
  "exp": $((`date +%s` + 3600))
}
EOF

  gcloud iam service-accounts sign-jwt --iam-account="${SERVICE_ACCOUNT_EMAIL}" jwt-claim.json "${output_file}"
  echo "JWT token for audience '${audience_path}' created in ${output_file}"
}

# --- First Call: Queue a prompt and get the prompt_id ---

# Create JWT for queue_prompt endpoint
create_jwt "/api/v1/queue_prompt" "token.jwt"

# Make the API call to queue a new prompt and store the prompt_id
PROMPT_ID=$(curl --silent \
--data "@workflows/sdxl.json" \
--header "Authorization: Bearer $(cat token.jwt)" \
--header "Content-Type: application/json" \
--request POST \
"https://${HOSTNAME}/api/v1/queue_prompt" | jq -r '.prompt_id')

if [[ -z "${PROMPT_ID}" ]]; then
  echo "Error: Failed to get prompt_id. Exiting."
  exit 1
fi

echo "Queued prompt successfully. The Prompt ID is: ${PROMPT_ID}"

# --- Second Call: Get the prompt history using the prompt_id ---

# Create a new JWT for the history endpoint, using the stored PROMPT_ID
create_jwt "/history/${PROMPT_ID}" "history-token.jwt"

# Make the API call to retrieve the history
HISTORY_RESPONSE=$(curl --silent \
--header "Authorization: Bearer $(cat history-token.jwt)" \
--header "Content-Type: application/json" \
--request GET \
"https://${HOSTNAME}/history/${PROMPT_ID}")

echo "History for prompt ${PROMPT_ID}:"
echo "${HISTORY_RESPONSE}"
