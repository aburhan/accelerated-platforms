# Copyright 2024 Google LLC
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

resource "google_storage_bucket" "federated_learning_cloud_storage_buckets" {
  for_each = var.federated_learning_cloud_storage_buckets

  force_destroy               = each.value.force_destroy
  location                    = var.cluster_region
  name                        = join("-", [local.terraform_project_id, local.unique_identifier_prefix, each.key])
  project                     = data.google_project.cluster.project_id
  uniform_bucket_level_access = true

  versioning {
    enabled = each.value.versioning_enabled
  }
}
