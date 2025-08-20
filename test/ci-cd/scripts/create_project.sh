#!/usr/bin/env bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script creates a new Google Cloud project, links it to a billing
# account, and sets a folder. It is designed to be run from a Cloud Build job.

# Exit immediately if a command exits with a non-zero status.
set -o errexit
# Exit if any unset variables are used.
set -o nounset
# Prevent silent failures in a pipeline.
set -o pipefail
# Log all commands being executed.
set -x

echo "Beginning Google Cloud project creation process..."
echo "---"

echo "Accessing 'project-creator-service-account' secret value."
PROJECT_CREATOR_SA=$(gcloud secrets versions access latest \
  --project="comfyui-ab10" \
  --secret="project-creator-service-account")

echo "Successfully retrieved service account: ${PROJECT_CREATOR_SA}"
echo "---"

echo "Accessing 'project-creator-billing-account-id' secret value."
PROJECT_CREATOR_BILLING_ACCOUNT=$(gcloud secrets versions access latest \
  --impersonate-service-account="${PROJECT_CREATOR_SA}" \
  --project="comfyui-ab10" \
  --secret="project-creator-billing-account-id" 2>&1 | grep -v 'impersonation')

echo "Successfully retrieved billing account ID."
echo "---"

echo "Accessing 'project-creator-folder-id' secret value."
PROJECT_CREATOR_FOLDER_ID=$(gcloud secrets versions access latest \
  --impersonate-service-account="${PROJECT_CREATOR_SA}" \
  --project="comfyui-ab10" \
  --secret="project-creator-folder-id" 2>&1 | grep -v 'impersonation')

echo "Successfully retrieved folder ID."
echo "---"

echo "Creating new project with ID: '${NEW_PROJECT_ID}' in folder: '${PROJECT_CREATOR_FOLDER_ID}'..."
gcloud projects create "${NEW_PROJECT_ID}" \
  --folder="${PROJECT_CREATOR_FOLDER_ID}" \
  --impersonate-service-account="${PROJECT_CREATOR_SA}" 2>&1 | grep -v 'impersonation'
echo "Project '${NEW_PROJECT_ID}' created successfully."
echo "---"

echo "Linking billing account to project '${NEW_PROJECT_ID}'..."
gcloud billing projects link "${NEW_PROJECT_ID}" \
  --billing-account="${PROJECT_CREATOR_BILLING_ACCOUNT}" \
  --impersonate-service-account="${PROJECT_CREATOR_SA}" 2>&1 | grep -v -E 'billingAccountName|impersonation'
echo "Billing account linked to project '${NEW_PROJECT_ID}' successfully."
echo "---"

echo "Script finished. Project creation and billing link complete."
