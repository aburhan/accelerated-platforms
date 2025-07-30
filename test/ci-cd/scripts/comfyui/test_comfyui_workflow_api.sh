#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

ls
# Define variables for clarity and ease of maintenance
WORKFLOW_DIR="./platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api"
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
create_jwt "/api/v1/queue_prompt" "token.jwt"

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

# --------------------------------------------------------

# --- Second Call: Poll for prompt history and output file ---
echo "Starting to poll for output for prompt_id: ${PROMPT_ID}..."
TIMEOUT=300 # 5 minutes
SLEEP_INTERVAL=5 # seconds
START_TIME=$(date +%s)

# Create a new JWT for the history endpoint, using the stored PROMPT_ID
create_jwt "/api/v1/history/${PROMPT_ID}" "history_token.jwt"

while (( $(date +%s) - START_TIME < TIMEOUT )); do
  HISTORY_RESPONSE=$(curl --silent \
  --header "Authorization: Bearer $(cat history_token.jwt)" \
  --header "Content-Type: application/json" \
  --request GET \
  "https://${HOSTNAME}/api/v1/history/${PROMPT_ID}")

  # Use a single jq filter to handle both 'video' and 'images' and dynamic keys
  FILENAME=$(echo "${HISTORY_RESPONSE}" | jq -r --arg prompt_id "${PROMPT_ID}" '
    .[$prompt_id].outputs[] | .video[0][0] // .images[0].filename
  ')

  STATUS=$(echo "${HISTORY_RESPONSE}" | jq -r --arg prompt_id "${PROMPT_ID}" '
    .[$prompt_id].status.status_str
  ')

  if [[ -n "${FILENAME}" ]]; then
    echo "Output found! Filename: ${FILENAME}"
    echo "Workflow Status: ${STATUS}"
    exit 0
  fi

  echo "Output not ready (status: ${STATUS}). Waiting ${SLEEP_INTERVAL} seconds..."
  sleep "${SLEEP_INTERVAL}"
done

echo "Error: Timeout reached after ${TIMEOUT} seconds. No output found."
exit 1
