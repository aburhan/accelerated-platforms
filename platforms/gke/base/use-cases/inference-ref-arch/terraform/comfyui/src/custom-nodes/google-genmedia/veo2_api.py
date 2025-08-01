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

# This is a preview version of veo2 custom node

from typing import List, Optional

import torch
from google import genai

from . import utils
from .config import get_gcp_metadata
from .constants import VEO2_MODEL_ID, VEO2_USER_AGENT
from .utils import validate_gcs_uri_and_image


class Veo2API:
    """
    A client for interacting with the Google Veo 2.0 API for video generation.
    """

    def __init__(
        self, project_id: Optional[str] = None, region: Optional[str] = None
    ) -> None:
        """
        Initializes the Veo2API client.

        Args:
            project_id: The GCP project ID. If None, it will be retrieved from GCP metadata.
            region: The GCP region. If None, it will be retrieved from GCP metadata.

        Raises:
            ValueError: If GCP Project or Zone cannot be determined.
        """
        self.project_id = project_id or get_gcp_metadata("project/project-id")
        self.region = region or "-".join(
            get_gcp_metadata("instance/zone").split("/")[-1].split("-")[:-1]
        )
        if not self.project_id:
            raise ValueError("GCP Project is required")
        if not self.region:
            raise ValueError("GCP region is required")
        print(f"Project is {self.project_id}, region is {self.region}")
        http_options = genai.types.HttpOptions(headers={"user-agent": VEO2_USER_AGENT})
        self.client = genai.Client(
            vertexai=True,
            project=self.project_id,
            location=self.region,
            http_options=http_options,
        )

        self.retry_count = 3  # Number of retries for transient errors
        self.retry_delay = 5  # Initial delay between retries (seconds)

    def generate_video_from_text(
        self,
        prompt: str,
        aspect_ratio: str,
        person_generation: str,
        duration_seconds: int,
        enhance_prompt: bool,
        sample_count: int,
        negative_prompt: Optional[str],
        seed: Optional[int],
    ) -> List[str]:
        """
        Generates video from a text prompt using the Veo 2.0 API.

        Args:
            prompt: The text prompt for video generation.
            aspect_ratio: The desired aspect ratio of the video (e.g., "16:9", "1:1").
            person_generation: Controls whether the model can generate people ("allow" or "dont_allow").
            duration_seconds: The desired duration of the video in seconds (5-8 seconds).
            enhance_prompt: Whether to enhance the prompt automatically.
            sample_count: The number of video samples to generate (1-4).
            negative_prompt: An optional prompt to guide the model to avoid generating certain things.
            seed: An optional seed for reproducible video generation.

        Returns:
            A list of file paths to the generated videos.

        Raises:
            ValueError: If input parameters are invalid (e.g., empty prompt, out-of-range duration/sample_count).
            RuntimeError: If video generation fails after retries, due to API errors, or unexpected issues.
        """
        if not prompt or not isinstance(prompt, str) or len(prompt.strip()) == 0:
            raise ValueError("Prompt cannot be empty for text-to-video generation.")
        if not (5 <= duration_seconds <= 8):
            raise ValueError(
                f"duration_seconds must be between 5 and 8, but got {duration_seconds}."
            )
        if not (1 <= sample_count <= 4):
            raise ValueError(
                f"sample_count must be between 1 and 4, but got {sample_count}."
            )
        return utils.generate_video_from_text(
            client=self.client,
            model=VEO2_MODEL_ID,
            prompt=prompt,
            aspect_ratio=aspect_ratio,
            person_generation=person_generation,
            duration_seconds=duration_seconds,
            enhance_prompt=enhance_prompt,
            sample_count=sample_count,
            negative_prompt=negative_prompt,
            seed=seed,
            retry_count=self.retry_count,
            retry_delay=self.retry_delay,
        )

    def generate_video_from_image(
        self,
        image: torch.Tensor,
        image_format: str,
        prompt: str,
        aspect_ratio: str,
        person_generation: str,
        duration_seconds: int,
        enhance_prompt: bool,
        sample_count: int,
        negative_prompt: Optional[str],
        seed: Optional[int],
    ) -> List[str]:
        """
        Generates video from an image input (as a torch.Tensor) using the Veo 2.0 API.

        Args:
            image: The input image as a torch.Tensor (ComfyUI format).
            image_format: The format of the input image (e.g., "PNG", "JPEG", "MP4").
            prompt: The text prompt for video generation.
            aspect_ratio: The desired aspect ratio of the video.
            person_generation: Controls whether the model can generate people.
            duration_seconds: The desired duration of the video in seconds.
            enhance_prompt: Whether to enhance the prompt automatically.
            sample_count: The number of video samples to generate.
            negative_prompt: An optional prompt to guide the model to avoid generating certain things.
            seed: An optional seed for reproducible video generation.

        Returns:
            A list of file paths to the generated videos.

        Raises:
            ValueError: If input parameters are invalid (e.g., empty prompt, unsupported image format, out-of-range duration/sample_count).
            RuntimeError: If video generation fails after retries, due to API errors, or unexpected issues.
        """
        if not prompt or not isinstance(prompt, str) or len(prompt.strip()) == 0:
            print(
                "Prompt is empty for image-to-video. Veo might use default interpretation of image."
            )

        if not (1 <= duration_seconds <= 8):
            raise ValueError(
                f"duration_seconds must be between 1 and 8, but got {duration_seconds}."
            )
        if not (1 <= sample_count <= 4):
            raise ValueError(
                f"sample_count must be between 1 and 4, but got {sample_count}."
            )

        if image is None:
            raise ValueError("Image input (torch.Tensor) cannot be None.")

        return utils.generate_video_from_image(
            client=self.client,
            model=VEO2_MODEL_ID,
            image=image,
            image_format=image_format,
            prompt=prompt,
            aspect_ratio=aspect_ratio,
            person_generation=person_generation,
            duration_seconds=duration_seconds,
            enhance_prompt=enhance_prompt,
            sample_count=sample_count,
            negative_prompt=negative_prompt,
            seed=seed,
            retry_count=self.retry_count,
            retry_delay=self.retry_delay,
        )

    def generate_video_from_gcsuri_image(
        self,
        gcsuri: str,
        image_format: str,
        prompt: str,
        aspect_ratio: str,
        person_generation: str,
        duration_seconds: int,
        enhance_prompt: bool,
        sample_count: int,
        negative_prompt: Optional[str],
        seed: Optional[int],
    ) -> List[str]:
        """
        Generates video from a Google Cloud Storage (GCS) image URI using the Veo 2.0 API.

        Args:
            gcsuri: The GCS URI of the input image (e.g., "gs://my-bucket/path/to/image.jpg").
            image_format: The format of the input image (e.g., "PNG", "JPEG", "MP4").
            prompt: The text prompt for video generation.
            aspect_ratio: The desired aspect ratio of the video.
            person_generation: Controls whether the model can generate people.
            duration_seconds: The desired duration of the video in seconds.
            enhance_prompt: Whether to enhance the prompt automatically.
            sample_count: The number of video samples to generate.
            negative_prompt: An optional prompt to guide the model to avoid generating certain things.
            seed: An optional seed for reproducible video generation.

        Returns:
            A list of file paths to the generated videos.

        Raises:
            ValueError: If input parameters are invalid (e.g., empty prompt, unsupported image format,
                        invalid GCS URI, or if the GCS object is not a valid image).
            RuntimeError: If video generation fails after retries, due to API errors, or unexpected issues.
        """
        if gcsuri is None:
            raise ValueError(
                "GCS URI for the image cannot be None for image-to-video generation."
            )
        if not prompt or not isinstance(prompt, str) or len(prompt.strip()) == 0:
            print(
                "Prompt is empty for image-to-video. Veo might use default interpretation of image."
            )

        if not (1 <= duration_seconds <= 8):
            raise ValueError(
                f"duration_seconds must be between 1 and 8, but got {duration_seconds}."
            )
        if not (1 <= sample_count <= 4):
            raise ValueError(
                f"sample_count must be between 1 and 4, but got {sample_count}."
            )

        valid_bucket, validation_message = validate_gcs_uri_and_image(gcsuri)
        if valid_bucket:
            print(validation_message)
        else:
            raise ValueError(validation_message)

        input_image_format_upper = image_format.upper()
        mime_type: str
        if input_image_format_upper == "PNG":
            mime_type = "image/png"
        elif input_image_format_upper == "JPEG":
            mime_type = "image/jpeg"
        elif input_image_format_upper == "MP4":
            mime_type = "image/mp4"
        else:
            raise ValueError(f"Unsupported image format: {image_format}")

        return utils.generate_video_from_gcsuri_image(
            client=self.client,
            model=VEO2_MODEL_ID,
            gcsuri=gcsuri,
            image_format=image_format,
            prompt=prompt,
            aspect_ratio=aspect_ratio,
            person_generation=person_generation,
            duration_seconds=duration_seconds,
            enhance_prompt=enhance_prompt,
            sample_count=sample_count,
            negative_prompt=negative_prompt,
            seed=seed,
            retry_count=self.retry_count,
            retry_delay=self.retry_delay,
        )
