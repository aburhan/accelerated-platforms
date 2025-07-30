
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
import os
import argparse
import json
import time
import requests
import google.auth.crypt
import google.auth.jwt
import pandas as pd
from tabulate import tabulate

# === CONFIGURATION ===
DEFAULT_WORKFLOWS_DIR = "workflows"


def generate_jwt_headers(sa_key_file: str, audience: str) -> dict:
    with open(sa_key_file, "r") as f:
        sa_info = json.load(f)

    signer = google.auth.crypt.RSASigner.from_service_account_info(sa_info)
    now = int(time.time())

    payload = {
        "iss": sa_info["client_email"],
        "sub": sa_info["client_email"],
        "aud": audience,
        "iat": now,
        "exp": now + 3600,
    }

    jwt_token = google.auth.jwt.encode(signer, payload).decode("utf-8")
    return {
        "Authorization": f"Bearer {jwt_token}",
        "Content-Type": "application/json",
    }


def queue_prompt(api_base: str, workflow_path: str, sa_key_file: str) -> str:
    with open(workflow_path, "r") as f:
        prompt_json = json.load(f)

    audience = f"{api_base}/queue_prompt"
    headers = generate_jwt_headers(sa_key_file, audience)
    response = requests.post(f"{api_base}/queue_prompt", json={"prompt": prompt_json}, headers=headers)
    response.raise_for_status()
    return response.json()["prompt_id"]


def get_image_metadata(filename: str, sa_key_file: str, api_base: str) -> dict:
    audience = f"{api_base}/image"
    headers = generate_jwt_headers(sa_key_file, audience)
    params = {"filename": filename, "type": "temp", "subfolder": ""}
    response = requests.get(f"{api_base}/image", headers=headers, params=params, stream=True)

    return {
        "size_bytes": len(response.content),
        "content_type": response.headers.get("Content-Type", "unknown"),
    }


def poll_for_output(api_base: str, prompt_id: str, sa_key_file: str, timeout: int = 300) -> dict:
    headers = generate_jwt_headers(sa_key_file, f"{api_base}/history/{prompt_id}")
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
                metadata = get_image_metadata(filename, sa_key_file, api_base)
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


def run_workflows(sa_key_file: str, workflows_dir: str, api_host: str):
    api_base = f"{api_host}/api/v1"
    results = []
    print(api_base)
    for file in os.listdir(workflows_dir):
        if not file.endswith(".json"):
            continue

        path = os.path.join(workflows_dir, file)
        print(f"Queuing: {file}")
        try:
            prompt_id = queue_prompt(api_base, path, sa_key_file)
            result = poll_for_output(api_base, prompt_id, sa_key_file)
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
    parser.add_argument("--sa", required=True, help="Path to service account JSON key")
    parser.add_argument("--workflows_dir", required=True, help="Path to workflows folder")
    parser.add_argument("--workflow_api", required=True, help="Workflow API host")
    args = parser.parse_args()

    run_workflows(sa_key_file=args.sa, workflows_dir=args.workflows_dir, api_host=args.workflow_api)
