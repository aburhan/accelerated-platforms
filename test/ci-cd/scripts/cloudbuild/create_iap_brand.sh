#!/usr/bin/env bash

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

source /workspace/build.env
if [ "${DEBUG,,}" == "true" ]; then
  set -o xtrace
fi

# Enable IAP
gcloud services enable iap.googleapis.com \
--project="${IAP_PROJECT_ID}"

# Create OAuth brand
while !  gcloud iap oauth-brands create \
  --application_title="IAP Secured Application" \
  --project="${IAP_PROJECT_ID}" \
  --quiet \
  --support_email="admin@ameenahb.altostrat.com"
do
  sleep 5
done
