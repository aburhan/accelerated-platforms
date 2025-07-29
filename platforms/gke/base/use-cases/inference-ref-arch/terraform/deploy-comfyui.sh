#!/usr/bin/env bash

# ... (existing copyright and set -o lines) ...

start_timestamp=$(date +%s)

MY_PATH="$(
  cd "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

# Set repository values
export ACP_REPO_DIR="$(realpath ${MY_PATH}/../../../../../../)"
export ACP_PLATFORM_BASE_DIR="${ACP_REPO_DIR}/platforms/gke/base"
export ACP_PLATFORM_CORE_DIR="${ACP_PLATFORM_BASE_DIR}/core"
export ACP_PLATFORM_USE_CASE_DIR="${ACP_PLATFORM_BASE_DIR}/use-cases/inference-ref-arch"

echo "--- Repository Path Variables ---"
echo "ACP_REPO_DIR: ${ACP_REPO_DIR}"
echo "ACP_PLATFORM_BASE_DIR: ${ACP_PLATFORM_BASE_DIR}"
echo "ACP_PLATFORM_CORE_DIR: ${ACP_PLATFORM_CORE_DIR}"
echo "ACP_PLATFORM_USE_CASE_DIR: ${ACP_PLATFORM_USE_CASE_DIR}"
echo "---------------------------------"


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
# The next line runs the core deploy script. We can add more checks after it.
CORE_TERRASERVICES_APPLY="${CORE_TERRASERVICES_APPLY[*]}" "${ACP_PLATFORM_CORE_DIR}/deploy.sh"

echo "--- Post Core Services Deployment Checks ---"
# After core services, you might want to verify some basic GCP resources
# For example, check if the GKE cluster was created.
# You'd need cluster_name and cluster_region available here for these checks.
# These variables typically come from the "set_environment_variables.sh" script.
# Let's assume they are set there and available after sourcing it.
echo "Verifying core GKE cluster existence..."
gcloud container clusters list --filter="name=${cluster_name}" --region="${cluster_region}" --project="${cluster_project_id}" --format="table(name,status)" || { echo "Core GKE cluster not found or not ready!"; exit 1; }
echo "--------------------------------------------"


# shellcheck disable=SC1091
source "${ACP_PLATFORM_USE_CASE_DIR}/terraform/_shared_config/scripts/set_environment_variables.sh"

echo "--- Post set_environment_variables.sh Sourcing ---"
# Verify variables set by the sourced script
echo "cluster_name: ${cluster_name}"
echo "cluster_region: ${cluster_region}"
echo "cluster_project_id: ${cluster_project_id}"
echo "--------------------------------------------------"


declare -a use_case_terraservices=(
  "initialize"
  "comfyui"
)
for terraservice in "${use_case_terraservices[@]}"; do
  echo "--- Deploying Terraservice: ${terraservice} ---"
  cd "${ACP_PLATFORM_USE_CASE_DIR}/terraform/${terraservice}" &&
    echo "Current directory: $(pwd)" &&
    terraform init &&
    terraform plan -input=false -out=tfplan &&
    terraform apply -input=false tfplan || exit 1
  rm tfplan
  echo "--- Terraservice ${terraservice} Deployment Complete ---"

  # Add specific checks AFTER 'comfyui' terraservice apply
  if [ "${terraservice}" == "comfyui" ]; then
    echo "--- Performing ComfyUI-specific Kubernetes checks ---"
    
    # Ensure kubectl context is set (redundant but safe)
    gcloud container clusters get-credentials "${cluster_name}" \
      --region "${cluster_region}" \
      --project "${cluster_project_id}" \
      --dns-endpoint --quiet
    
    NAMESPACE="default" # Adjust if comfyui deploys to a specific namespace
    DEPLOYMENT_NAME="comfyui-deployment" # Adjust to your actual deployment name

    echo "Checking for Kubernetes Deployment: ${DEPLOYMENT_NAME} in namespace ${NAMESPACE}..."
    if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}"; then
      echo "Error: ComfyUI deployment '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'."
      exit 1
    fi

    echo "Waiting for ComfyUI deployment '${DEPLOYMENT_NAME}' rollout to complete..."
    # The timeout here ensures the build doesn't hang indefinitely if deployment fails.
    kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=5m || {
      echo "Error: ComfyUI deployment '${DEPLOYMENT_NAME}' did not become ready."
      kubectl describe deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" # Print details for debugging
      exit 1
    }
    echo "ComfyUI deployment '${DEPLOYMENT_NAME}' is ready."

    # Verify Pods are running
    echo "Checking ComfyUI pods in namespace ${NAMESPACE}..."
    if ! kubectl get pods -n "${NAMESPACE}" -l app=${DEPLOYMENT_NAME} -o wide | grep "Running"; then
      echo "Error: ComfyUI pods are not in 'Running' state."
      kubectl get pods -n "${NAMESPACE}" -l app=${DEPLOYMENT_NAME} -o wide # Show problematic pods
      exit 1
    fi

    # Verify Service (if exposed internally or externally)
    SERVICE_NAME="comfyui-service" # Adjust to your actual service name
    echo "Checking Kubernetes Service: ${SERVICE_NAME} in namespace ${NAMESPACE}..."
    if ! kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}"; then
      echo "Error: ComfyUI service '${SERVICE_NAME}' not found."
      exit 1
    fi

    # Verify Ingress (if exposed via Ingress)
    INGRESS_NAME="comfyui-ingress" # Adjust to your actual ingress name
    echo "Checking Kubernetes Ingress: ${INGRESS_NAME} in namespace ${NAMESPACE}..."
    if ! kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}"; then
      echo "Warning: ComfyUI ingress '${INGRESS_NAME}' not found. This might be expected if not using Ingress."
      # Don't exit 1 here unless ingress is strictly required for this stage
    else
        echo "Ingress details:"
        kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" -o json | jq '.status.loadBalancer.ingress[0].ip' || jq '.status.loadBalancer.ingress[0].hostname'
    fi

    echo "--- ComfyUI-specific Kubernetes checks complete ---"
  fi
done

# shellcheck disable=SC2154
gcloud container clusters get-credentials "${cluster_name}" \
  --region "${cluster_region}" \
  --project "${cluster_project_id}" \
  --dns-endpoint

end_timestamp=$(date +%s)
total_runtime_value=$((end_timestamp - start_timestamp))
echo "comfyui deploy total runtime: $(date -d@${total_runtime_value} -u +%H:%M:%S)"
