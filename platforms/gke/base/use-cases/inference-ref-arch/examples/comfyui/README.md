# ComfyUI reference implementation

## Pull the source code

- Open [Cloud Shell](https://cloud.google.com/shell).

  To deploy this reference implementation, you need Terraform >= 1.8.0. For more
  information about installing Terraform, see
  [Install Terraform](https://developer.hashicorp.com/terraform/install).

- Clone the repository and change directory to the guide directory

  ```
  git clone https://github.com/GoogleCloudPlatform/comfyui-ab4 && \
  cd comfyui-ab4 && \
  export ACP_REPO_DIR="$(pwd)"
  ```

  To set the `ACP_REPO_DIR` value for new shell instances, write the value to
  your shell initialization file.

  `bash`

  ```
  sed -n -i -e '/^export ACP_REPO_DIR=/!p' -i -e '$aexport ACP_REPO_DIR="'"${ACP_REPO_DIR}"'"' ${HOME}/.bashrc
  ```

  `zsh`

  ```
  sed -n -i -e '/^export ACP_REPO_DIR=/!p' -i -e '$aexport ACP_REPO_DIR="'"${ACP_REPO_DIR}"'"' ${HOME}/.zshrc
  ```

## Configure

Terraform loads variables in the following order, with later sources taking
precedence over earlier ones:

- Environment variables (`TF_VAR_<variable_name>`)
- Any `*.auto.tfvars` or files, processed in lexical order of their filenames.
- Any `-var` and `-var-file` options on the command line, in the order they are
  provided.

- Set the platform defaults project ID

  ```
  export TF_VAR_platform_default_project_id="<PROJECT_ID>"
  ```

  **-- OR --**

  ```
  platform_default_project_id="<PROJECT_ID>"
  sed -i '/^platform_default_project_id[[:blank:]]*=/{h;s/=.*/= "'"${platform_default_project_id}"'"/};${x;/^$/{s//platform_default_project_id = "'"${platform_default_project_id}"'"/;H};x}' ${ACP_REPO_DIR}/platforms/gke/base/_shared_config/platform.auto.tfvars
  ```

- Optional : By default, the platform name is set to `dev`. If you want to
  change it, set the platform name

  ```
  platform_name="<PLATFORM_NAME>"
  sed -i '/^platform_name[[:blank:]]*=/{h;s/=.*/= "'"${platform_name}"'"/};${x;/^$/{s//platform_name="'"${platform_name}"'"/;H};x}' ${ACP_REPO_DIR}/platforms/gke/base/_shared_config/platform.auto.tfvars
  ```

- Optional : Run the following step if you want to run ComfyUI on an accelerator
  other than L4 which is the default accelerator for this deployment.

  ```
  comfyui_accelerator_type="<ACCELERATOR>"
  sed -i '/^comfyui_accelerator_type[[:blank:]]*=/{h;s/=.*/= "'"${comfyui_accelerator_type}"'"/};${x;/^$/{s//comfyui_accelerator_type="'"${comfyui_accelerator_type}"'"/;H};x}' ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/_shared_config/comfyui.auto.tfvars
  ```

  Valid values for `ACCELERATOR` are:

  - `nvidia-h100-80gb`
  - `nvidia-tesla-a100`
  - `nvidia-l4(default)`

## Configure Identity-Aware Proxy (IAP)

Identity-Aware Proxy (IAP) lets you establish a central authorization layer for
applications accessed by HTTPS, so you can use an application-level access
control model instead of relying on network-level firewalls.

IAP policies scale across your organization. You can define access policies
centrally and apply them to all of your applications and resources. When you
assign a dedicated team to create and enforce policies, you protect your project
from incorrect policy definition or implementation in any application.

For more information on IAP, see the
[Identity-Aware Proxy documentation](https://cloud.google.com/iap/docs/concepts-overview#gke)

### Configure OAuth consent screen for IAP

For this guide we will configure a generic OAuth consent screen setup for
internal use. Internal use means that only users within your organization can be
granted IAM permissions to access the IAP secured applications and resource.

See the
[Configuring the OAuth consent screen documentation](https://developers.google.com/workspace/guides/configure-oauth-consent)
for additional information

- Set environment variables.

  ```shell
  source "${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/_shared_config/scripts/set_environment_variables.sh"
  ```

- Ensure that IAP is enabled.

  ```shell
  gcloud services enable iap.googleapis.com \
  --project="${comfyui_iap_oath_branding_project_id}"
  ```

- Check if the branding is already configured.

  ```shell
  gcloud iap oauth-brands list \
  --project="${comfyui_iap_oath_branding_project_id}"
  ```

  > If an entry is displayed, the branding is already configured.

- Configure the branding.

  ```shell
  gcloud iap oauth-brands create \
  --application_title="IAP Secured Application" \
  --project="${comfyui_iap_oath_branding_project_id}" \
  --support_email="<SUPPORT_EMAIL_ADDRESS>"
  ```

  Replace `<SUPPORT_EMAIL_ADDRESS>` with a group email address that you are a
  manager on or your personal email address. The email address should be
  supplied without the domain.

### Default IAP access

For simplicity, in this guide access to the IAP secured applications will be
configure to allow all users in the organization. Access can be configured per
IAP application or resources.

- Set the IAP allow domain

  ```
  IAP_DOMAIN=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | awk -F@ '{print $2}')
  echo "IAP_DOMAIN=${IAP_DOMAIN}"
  ```

  **If the domain of the active `gcloud` user is different from the organization
  that the `comfyui_iap_oath_branding_project_id` project is in, you will need
  to manually set `IAP_DOMAIN` environment variable**

  ```
  IAP_DOMAIN="<project_id's organization domain>"
  ```

- Set the IAP domain in the configuration file

  ```
  sed -i '/^comfyui_iap_domain[[:blank:]]*=/{h;s/=.*/= "'"${IAP_DOMAIN}"'"/};${x;/^$/{s//comfyui_iap_domain="'"${IAP_DOMAIN}"'"/;H};x}' ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/_shared_config/comfyui.auto.tfvars
  ```

## Deploy

```
${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/deploy-comfyui.sh
```

## Workflow

The `deploy-comfyui.sh` script will perform the following steps:

- Set up base GKE cluster platform.
- Create resources required to deploy ComfyUI on the GKE cluster and access it.
- Deploy ComfyUI on `nvidia-l4` accelerator and make the ComfyUI accessible
  through Identity-Aware Proxy.

## Verify ComfyUI deployment is up and running

- Set the environment variables

  ```
  source "${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/_shared_config/scripts/set_environment_variables.sh"
  ```

- Source GKE cluster credentials

  ```
  gcloud container clusters get-credentials ${cluster_name} \
  --dns-endpoint \
  --location="${cluster_region}" \
  --project="${cluster_project_id}"
  ```

- Check the ComfyUI deployment

  ```
  watch --color --interval 5 --no-title \
  "kubectl --namespace=${comfyui_kubernetes_namespace} get deployment/${comfyui_app_name}-${comfyui_accelerator_type} | GREP_COLORS='mt=01;92' egrep --color=always -e '^' -e '1/1     1            1'"
  ```

- When the deployment is ready, you will output similar to the following

  ```
  NAME                READY   UP-TO-DATE   AVAILABLE   AGE
  comfyui-nvidia-l4   1/1     1            1           XXXX
  ```

- Output the ComfyUI URL.

  ```
  echo -e "\nComfyUI URL: https://${comfyui_endpoints_hostname}\n"
  ```

- Open the ComfyUI URL in a web browser.

> [!TIP]  
> If the browser doesn't load ComfyUI, the SSL certificate could still be
> getting provisioned. Check the status of the certificate by running the
> following command:
>
> `gcloud compute ssl-certificates describe ${comfyui_ssl_certificate_name} --project ${cluster_project_id} --format=json | jq -r '.managed.status'`
>
> If the output of the command is `PROVISIONING`, it means the certificate has
> not been provisioned yet. Wait for the status to change to `ACTIVE`

## Load models in ComfyUI

In ComfyUI, click the `Model Library(m)` menu shown with the box icon on the
left side. You will see empty folders including checkpoint folder. When ComfyUI
was deployed, there were three GCS buckets created with the suffixes
`comfyui-input`, `comfyui-output` and `comfyui-models` and these buckets are
mounted on the container that is running ComfyUI. The ComfyUI Model Library is
mounted on the bucket with the suffix `comfyui-models`. If you want to use a
model in ComfyUI, you can download its checkpoint file to that bucket and it
will show up in ComfyUI Model Library.

You can use different methods to download checkpoint files to the bucket. These
files can be large and the disk space where you are running this guide could be
limited. So, you can use perform the copy operation using a K8s job or
Cloudbuild pipeline or some thing else.

- In this guide, we will use Cloudbuild pipeline to copy the following
  checkpoint files for Stable diffusion base and refiner models, LTXV model and
  Flux text encoder from Hugging Face to the GCS bucket.

  - https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
  - https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner-1.0.safetensors
  - https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.1.safetensors
  - https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors

- Run the following command to trigger cloudbuild pipeline to copy checkpoint
  files:

  ```
  gcloud builds submit \
  --config="${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/comfyui/copy-checkpoints/cloudbuild.yaml" \
  --gcs-source-staging-dir="gs://${comfyui_cloudbuild_source_bucket_name}/source" \
  --no-source \
  --project="${cluster_project_id}" \
  --service-account="${comfyui_cloudbuild_service_account_id}" \
  --substitutions="_BUCKET_NAME=${comfyui_cloud_storage_model_bucket_name}"
  ```

  It will take around 6 minutes to finish.

- When the copy is finished, you will see the output similar to the following:

  ```
  ID: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  CREATE_TIME: YYYY-MM-DDTHH:MM:SS+ZZ:ZZ
  DURATION: #M##S
  SOURCE: -
  IMAGES: -
  STATUS: SUCCESS
  ```

- Refresh ComfyUI and click on `checkpoints` in MODEL LIBRARY, you will see
  three checkpoint files available to use. These files will be named
  `sd_xl_base_1.0.safetensors`, `sd_xl_refiner_1.0.safetensors` and
  `ltx-video-2b-v0.9`

- Click on `text_encoders` on ComfyUI in MODEL_LIBRARY, you will see a file
  named `t5xxl_fp16`

- You can download more models to use in your ComfyUI instance in a similar
  fashion.
- Get creative and storyboard your ideas on ComfyUI!

## ComfyUI workflows

This guide provides example workflows out of the box. On ComfyUI, click on
WORKFLOWS. You should see the following workflow files:

- `imagen3-text-to-image` : This workflow shows text to image generation with
  Google's Imagen3 model.
- `imagen4-text-to-image` : This workflow shows text to image generation with
  Google's Imagen4 model.
- `imagen4-veo2-text-to-image-to-video` : This workflow shows text to image
  generation with Google's Imagen4 model and image to video generation with
  Google's Veo2 model.
- `ltxv-text-to-video` : This workflow shows text to video generation with
  Lightricks' LTXV-Video model.
- `sdxl-text-to-image` : This workflow shows text to image generation with
  Stable Diffusion refiner model.
- `veo2-text-to-video` : This workflow shows text to video generation with
  Google's Veo2 model.

> [!WARNING]  
> ComfyUI custom nodes to Imagen3, Imagen4, Veo2 and Veo3 are in preview mode.

Click any of the workflow files to open the workflow and click `Run` to see the
results.

You can create additional workflows using the Imagen and Veo custom nodes. To
view these custom nodes, right click in the ComfyUI screen, choose `Google AI`
in the dropdown, it will show the Imagen and Veo custom nodes.

## [Optional] Setup a Workflow API for batch operation

In this section you can deploy a Workflow API to front the ComfyUI deployment
and use it in batch mode by submitting ComfyUI workflows exported as .json
objects to the Workflow API. ComfyUI will still output the generated media in
the output bucket.

- Deploy Workflow API resources:

  ```shell
  cd ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api && \
  terraform init && \
  terraform plan -input=false -out=tfplan && \
  terraform apply -input=false tfplan && \
  rm tfplan
  ```

- Set the environment variables

  ```
  source "${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/_shared_config/scripts/set_environment_variables.sh"
  ```

- Verify that the Workflow API has been successfully deployed:

  ```
  kubectl --namespace=${comfyui_kubernetes_namespace} get deploy,svc
  ```

  Response should look like this:

  ```
  NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
  deployment.apps/comfyui-nvidia-l4   1/1     1            1           XXXX
  deployment.apps/workflow-api        1/1     1            1           XXXX

  NAME                        TYPE        CLUSTER-IP        EXTERNAL-IP   PORT(S)    AGE
  service/comfyui-nvidia-l4   ClusterIP   ###.###.###.###   <none>        8188/TCP   XXXX
  service/workflow-api        ClusterIP   ###.###.###.###   <none>        8080/TCP   XXXX
  ```

- In order to send a sample workflow the active `gcloud` account needs to have
  the
  [Service Account Token Creator](https://cloud.google.com/iam/docs/roles-permissions/iam#iam.serviceAccountTokenCreator)
  role for the Workflow API service account. The following command will add the
  role to the active `gcloud` account.

  ```shell
  gcloud iam service-accounts add-iam-policy-binding ${workflow_api_service_account_email} \
  --member="user:$(gcloud auth list --filter=status:ACTIVE --format="value(account)")" \
  --project="${workflow_api_service_account_project_id}" \
  --role="roles/iam.serviceAccountTokenCreator"
  ```

- Send a sample workflow to the Workflow API.

  - Generate JSON Web Token (JWT)

    ```shell
    cd ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api && \
    cat > jwt-claim.json << EOF
    {
      "iss": "${workflow_api_service_account_email}",
      "sub": "${workflow_api_service_account_email}",
      "aud": "https://${workflow_api_endpoints_hostname}/api/v1/queue_prompt",
      "iat": $(date +%s),
      "exp": $((`date +%s` + 3600))
    }
    EOF
    ```

    ```shell
    gcloud iam service-accounts sign-jwt --iam-account="${workflow_api_service_account_email}" jwt-claim.json token.jwt
    ```

  - Send the request.

    ```shell
    cd ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api && \
    curl \
    --data "@workflows/sdxl.json" \
    --header "Authorization: Bearer $(cat token.jwt)" \
    --header "Content-Type: application/json" \
    --request POST \
    https://${workflow_api_endpoints_hostname}/api/v1/queue_prompt
    ```

> [!TIP]  
> If you get any of the following errors:
>
> `curl: (35) Recv failure: Connection reset by peer` or
> `curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to ...`
>
> It means that the SSL certificate could still be provisioning. You can check
> the status of the SSL certificate by running the following command:
>
> `gcloud compute ssl-certificates describe ${workflow_api_endpoints_ssl_certificate_name} --project ${cluster_project_id} --format=json | jq -r '.managed.status'`
>
> If the output of the command is `PROVISIONING`, it means the certificate has
> not been provisioned yet. Wait for the status to change to `ACTIVE`

- The response should look like this:

  ```shell
  {"prompt_id":"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX","number":##}
  ```

## Teardown

- Destroy the Workflow API resources.

  ```shell
  cd ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/workflow_api && \
  terraform init &&
  terraform destroy -auto-approve
  ```

- Teardown the ComfyUI platform

  ```shell
  ${ACP_REPO_DIR}/platforms/gke/base/use-cases/inference-ref-arch/terraform/teardown-comfyui.sh
  ```
