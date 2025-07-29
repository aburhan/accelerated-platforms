# TODO
```sh
export workflow_path=test/ci-cd/scripts/comfyui/workflows
export sa_path=test/ci-cd/scripts/comfyui/service-account.json
export workflow_api="https://workflow-api.comfyui.inf-dev.endpoints.comfyui-ab3.cloud.goog"
python test/ci-cd/scripts/comfyui/cli.py --sa $sa_path --workflows_dir $workflow_path --workflow_api $workflow_api
```