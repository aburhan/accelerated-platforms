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

STEP_ID=${1}
TEARDOWN_SCRIPT="${2}"

exit_handler() {
  exit_code=$?

  if [ ${exit_code} -ne 0 ]; then
    echo "- ${STEP_ID}" >>/workspace/build-failed.lock
  fi

  exit 0
}
trap exit_handler EXIT

${TEARDOWN_SCRIPT}
