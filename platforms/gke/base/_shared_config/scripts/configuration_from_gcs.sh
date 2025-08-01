#!/bin/bash
#
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -o errexit
set -o nounset
set -o pipefail

MY_PATH="$(
  cd "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

# Set repository values
ACP_REPO_DIR="$(realpath "${MY_PATH}"/../../../../../)"
ACP_PLATFORM_BASE_DIR="${ACP_REPO_DIR}/platforms/gke/base"

echo "Downloading Kubernetes files..."
gcloud storage cp \
  --preserve-symlinks \
  --recursive \
  "gs://${terraform_bucket_name}/terraform/configuration/kubernetes/*" \
  "${MY_PATH}/../../kubernetes"

if [[ ! -v GCS_SHARED_CONFIG_PATHS ]]; then
  GCS_SHARED_CONFIG_PATHS=($(gcloud storage ls -r gs://${terraform_bucket_name}/terraform/configuration/ | grep /_shared_config/: | tr '\n' ' '))
fi

for GCS_SHARED_CONFIG_PATH in "${GCS_SHARED_CONFIG_PATHS[@]}"; do
  GCS_SHARED_CONFIG_PATH="${GCS_SHARED_CONFIG_PATH::-2}"
  echo "Downloading configurations(${GCS_SHARED_CONFIG_PATH})..."
  folder_path=${GCS_SHARED_CONFIG_PATH#*/terraform/configuration/}

  gcloud storage cp \
    --preserve-symlinks \
    --recursive \
    "${GCS_SHARED_CONFIG_PATH}/*" \
    "${ACP_PLATFORM_BASE_DIR}/${folder_path}/"
done
