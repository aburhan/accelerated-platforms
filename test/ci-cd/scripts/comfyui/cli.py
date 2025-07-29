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
import os
import argparse
import json
import time
import requests
# Removed google.auth.crypt and google.auth.jwt
import google.auth
import pandas as pd
from tabulate import tabulate

# === CONFIGURATION ===
DEFAULT_WORKFLOWS_DIR = "workflows"

def get_authenticated_headers(audience: str) -> dict:
    """
    Generates authenticated headers using the default credentials
    available in the environment (e.g., Cloud Build service account).
    """
    credentials, project = google.auth.default()

    # Create a Request object to get the ID token
    auth_req = google.auth.transport.requests.Request()
    credentials.refresh(auth_req) # Ensure credentials are fresh

    if hasattr(credentials, 'token') and credentials.token:
        try:
            # This is the correct way to get an ID token for IAP-secured endpoints
            id_token = google.auth.jwt.encode(
                google.auth.crypt.RSASigner.from_service_account_info(credentials._service_account_info),
                google.auth.jwt.AccessTokenInfo(audience)
            ).decode("utf-8")
            return {
                "Authorization": f"Bearer {id_token}",
                "Content-Type": "application/json",
            }
        except AttributeError:
            return {
                "Authorization": f"Bearer {credentials.token}",
                "Content-Type": "application/json",
            }
    else:
        from google.oauth2 import id_token as id_token_module
        from google.auth.transport import requests as google_requests

        try:
            # Cloud Build service account's token should be discoverable by default
            # but getting an ID token requires a specific audience.
            id_token = id_token_module.fetch_id_token(google_requests.Request(), audience)
            return {
                "Authorization": f"Bearer {id_token}",
                "Content-Type": "application/json",
            }
        except Exception as e:
            print(f"Warning: Could not fetch ID token with audience {audience}. Error: {e}")
            # Fallback to general access token if ID token fails, though not ideal for IAP.
            # This assumes the target API can accept a standard access token.
            if credentials.token:
                return {
                    "Authorization": f"Bearer {credentials.token}",
                    "Content-Type": "application/json",
                }
            else:
                raise RuntimeError("Could not obtain any authentication token.")


def queue_prompt(api_base: str, workflow_path: str) -> str:
    with open(workflow_path, "r") as f:
        prompt_json = json.load(f)

    audience = f"{api_base}" 
    headers = get_authenticated_headers(audience)
    response = requests.post(f"{api_base}/queue_prompt", json={"prompt": prompt_json}, headers=headers)
    response.raise_for_status()
    return response.json()["prompt_id"]


def get_image_metadata(filename: str, api_base: str) -> dict:
    audience = f"{api_base}"
    headers = get_authenticated_headers(audience)
    params = {"filename": filename, "type": "temp", "subfolder": ""}
    response = requests.get(f"{api_base}/image", headers=headers, params=params, stream=True)
    response.raise_for_status() 
    return {
        "size_bytes": len(response.content),
        "content_type": response.headers.get("Content-Type", "unknown"),
    }


def poll_for_output(api_base: str, prompt_id: str, timeout: int = 300) -> dict: 
    audience = f"{api_base}" # Audience should be the base URL of the IAP-secured resource
    headers = get_authenticated_headers(audience)
    start = time.time()

    while time.time() - start < timeout:
        resp = requests.get(f"{api_base}/history/{prompt_id}", headers=headers)
        if resp.status_code == 200:
            data = resp.json()
            prompt_data = data.get(prompt_id, {})
            outputs = prompt_data.get("outputs", {})
            model = next(
                (n["inputs"]["model"] for n in list(data.values())[0]["prompt"][2].values() if "model" in n.get("inputs", {})),
                "unknown"
            )
            output = list(data.values())[0].get("outputs", {}).get("2", {})
            filename = output.get("video", [[None]])[0][0] if "video" in output else output.get("images", [{}])[0].get("filename")
            status = list(data.values())[0].get("status", {}).get("status_str")

            if filename:
                metadata = get_image_metadata(filename, api_base) 
                return {
                    "prompt_id": prompt_id,
                    "output_file": filename,
                    "model": model,
                    "type": metadata["content_type"],
                    "size_bytes": metadata["size_bytes"],
                    "workflow_status": status,
                }
        time.sleep(2)
    return {"workflow_status": "timeout", "output_file": None, "size_bytes": 0, "type": "unknown", "model": "unknown"}


def run_workflows(workflows_dir: str, api_host: str):
    # Use the base URL for the API as the audience for IAP
    api_base = f"{api_host}/api/v1"
    results = []
    print(f"API Base URL: {api_base}")

    for file in os.listdir(workflows_dir):
        if not file.endswith(".json"):
            continue

        path = os.path.join(workflows_dir, file)
        print(f"Queuing: {file}")
        try:
            prompt_id = queue_prompt(api_base, path)
            result = poll_for_output(api_base, prompt_id)
            result["workflow_file"] = file
        except Exception as e:
            result = {
                "workflow_file": file,
                "prompt_id": "N/A",
                "output_file": "N/A",
                "model": "N/A",
                "type": "N/A",
                "size_bytes": "N/A",
                "workflow_status": f"ERROR: {str(e)}",
            }
        results.append(result)

    df = pd.DataFrame(results)
    print("\n Final Report:\n")
    print(tabulate(df, headers='keys', tablefmt='grid', showindex=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run and validate ComfyUI workflows")
    parser.add_argument("--workflows_dir", required=True, help="Path to workflows folder")
    parser.add_argument("--workflow_api", required=True, help="Workflow API host")
    args = parser.parse_args()

    run_workflows(workflows_dir=args.workflows_dir, api_host=args.workflow_api) # Removed sa_key_file
