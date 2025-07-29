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
set -o errexit
set -o nounset
set -o pipefail # Added pipefail for better error handling in pipelines

start_timestamp=$(date +%s)

MY_PATH="$(
  cd "$(dirname "$0")" >/dev/null 2>&1 || exit 1 # Added || exit 1 for safety
  pwd -P
)"

# --- Path Verification Helper Function ---
# This function checks if a given path exists and is a directory or file.
# Exits with an error if the path doesn't exist.
verify_path_exists() {
  local path="$1"
  local type="$2" # "dir" or "file"
  local description="$3"

  if [ "${type}" == "dir" ]; then
    if [ ! -d "${path}" ]; then
      echo "Error: Directory '${description}' expected at '${path}' does not exist." >&2
      exit 1
    fi
  elif [ "${type}" == "file" ]; then
    if [ ! -f "${path}" ]; then
      echo "Error: File '${description}' expected at '${path}' does not exist." >&2
      exit 1
    fi
  else
    echo "Error: Invalid type '${type}' for path verification. Use 'dir' or 'file'." >&2
    exit 1
  fi
  echo "Verified: ${description} exists at '${path}'."
}

# Set repository values
export ACP_REPO_DIR="$(realpath "${MY_PATH}/../../../../../../")"
verify_path_exists "${ACP_REPO_DIR}" "dir" "ACP_REPO_DIR (repository root)"

export ACP_PLATFORM_BASE_DIR="${ACP_REPO_DIR}/platforms/gke/base"
verify_path_exists "${ACP_PLATFORM_BASE_DIR}" "dir" "ACP_PLATFORM_BASE_DIR"

export ACP_PLATFORM_CORE_DIR="${ACP_PLATFORM_BASE_DIR}/core"
verify_path_exists "${ACP_PLATFORM_CORE_DIR}" "dir" "ACP_PLATFORM_CORE_DIR"

export ACP_PLATFORM_USE_CASE_DIR="${ACP_PLATFORM_BASE_DIR}/use-cases/inference-ref-arch"
verify_path_exists "${ACP_PLATFORM_USE_CASE_DIR}" "dir" "ACP_PLATFORM_USE_CASE_DIR"

echo "--- Repository Path Variables Verified ---"
echo "ACP_REPO_DIR: ${ACP_REPO_DIR}"
echo "ACP_PLATFORM_BASE_DIR: ${ACP_PLATFORM_BASE_DIR}"
echo "ACP_PLATFORM_CORE_DIR: ${ACP_PLATFORM_CORE_DIR}"
echo "ACP_PLATFORM_USE_CASE_DIR: ${ACP_PLATFORM_USE_CASE_DIR}"
echo "----------------------------------------"


# Set use-case specific values
export TF_VAR_initialize_backend_use_case_name="inference-ref-arch/terraform"
export TF_VAR_resource_name_prefix="inf"

echo "--- Terraform Variable Exports ---"
echo "TF_VAR_initialize_backend_use_case_name: ${TF_VAR_initialize_backend_use_case_name}"
echo "TF_VAR_resource_name_prefix: ${TF_VAR_resource_name_prefix}"
echo "----------------------------------"

declare -a CORE_TERRASERVICES_APPLY=(
  "networking"
  "container_cluster"
  "cloudbuild/initialize"
  "workloads/cluster_credentials"
  "custom_compute_class"
  "workloads/auto_monitoring"
  "workloads/custom_metrics_adapter"
  "workloads/inference_gateway"
  "workloads/priority_class"
)

# Verify the core deploy script exists before calling it
CORE_DEPLOY_SCRIPT="${ACP_PLATFORM_CORE_DIR}/deploy.sh"
verify_path_exists "${CORE_DEPLOY_SCRIPT}" "file" "Core Deploy Script"

# The next line runs the core deploy script.
CORE_TERRASERVICES_APPLY="${CORE_TERRASERVICES_APPLY[*]}" "${CORE_DEPLOY_SCRIPT}"


echo "--- Post Core Services Deployment Checks ---"
# Assuming 'cluster_name', 'cluster_region', 'cluster_project_id' are set by the core deploy script
# or by 'set_environment_variables.sh' which is sourced later.
# If these variables might not be set yet, move this check *after* sourcing.
# For now, we'll assume they will be set when this line executes.
# A more robust check might involve sourcing set_environment_variables.sh earlier if safe.
# Or, make sure the core deploy script itself outputs these values.
if [ -n "${cluster_name:-}" ] && [ -n "${cluster_region:-}" ] && [ -n "${cluster_project_id:-}" ]; then
  echo "Verifying core GKE cluster existence using: ${cluster_name}, ${cluster_region}, ${cluster_project_id}"
  gcloud container clusters list --filter="name=${cluster_name}" --region="${cluster_region}" --project="${cluster_project_id}" --format="table(name,status)" \
    || { echo "Core GKE cluster not found or not ready! Cannot proceed."; exit 1; }
else
  echo "Warning: GKE cluster variables (cluster_name, cluster_region, cluster_project_id) not set after core deploy. Cannot verify cluster existence at this stage."
fi
echo "--------------------------------------------"


# shellcheck disable=SC1091
SHARED_ENV_SCRIPT="${ACP_PLATFORM_USE_CASE_DIR}/terraform/_shared_config/scripts/set_environment_variables.sh"
verify_path_exists "${SHARED_ENV_SCRIPT}" "file" "Shared Environment Variables Script"
source "${SHARED_ENV_SCRIPT}"

echo "--- Post set_environment_variables.sh Sourcing ---"
# Verify variables set by the sourced script
if [ -z "${cluster_name:-}" ]; then echo "Error: cluster_name not set by shared environment script."; exit 1; fi
if [ -z "${cluster_region:-}" ]; then echo "Error: cluster_region not set by shared environment script."; exit 1; fi
if [ -z "${cluster_project_id:-}" ]; then echo "Error: cluster_project_id not set by shared environment script."; exit 1; fi

echo "cluster_name: ${cluster_name}"
echo "cluster_region: ${cluster_region}"
echo "cluster_project_id: ${cluster_project_id}"
echo "--------------------------------------------------"


declare -a use_case_terraservices=(
  "initialize"
  "comfyui"
)
for terraservice in "${use_case_terraservices[@]}"; do
  TERRASERVICE_PATH="${ACP_PLATFORM_USE_CASE_DIR}/terraform/${terraservice}"
  verify_path_exists "${TERRASERVICE_PATH}" "dir" "Terraservice directory for ${terraservice}"



end_timestamp=$(date +%s)
total_runtime_value=$((end_timestamp - start_timestamp))
echo "comfyui deploy total runtime: $(date -d@${total_runtime_value} -u +%H:%M:%S)"
