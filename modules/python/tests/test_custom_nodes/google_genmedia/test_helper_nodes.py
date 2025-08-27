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

import unittest
from unittest.mock import patch, MagicMock, mock_open
import torch
import numpy as np
import sys
from unittest.mock import MagicMock

sys.modules["folder_paths"] = MagicMock()
from src.custom_nodes.google_genmedia.helper_nodes import (
    VeoVideoToVHSNode,
    VeoVideoSaveAndPreview,
)


class TestVeoVideoToVHSNode(unittest.TestCase):
    def setUp(self):
        self.node = VeoVideoToVHSNode()

    @patch(
        "src.custom_nodes.google_genmedia.helper_nodes.os.path.exists",
        return_value=True,
    )
    @patch(
        "src.custom_nodes.google_genmedia.helper_nodes.os.path.isfile",
        return_value=True,
    )
    @patch("src.custom_nodes.google_genmedia.helper_nodes.cv2.VideoCapture")
    def test_convert_videos_success(self, mock_video_capture, mock_isfile, mock_exists):
        # Arrange
        mock_cap_instance = MagicMock()
        mock_cap_instance.isOpened.return_value = True
        mock_cap_instance.get.side_effect = [
            240,
            1920,
            1080,
        ]  # total_frames, width, height
        mock_cap_instance.read.return_value = (
            True,
            np.zeros((1080, 1920, 3), dtype=np.uint8),
        )
        mock_video_capture.return_value = mock_cap_instance

        video_paths = ["/fake/video1.mp4"]

        # Act
        result = self.node.convert_videos(video_paths)

        # Assert
        self.assertIsInstance(result, tuple)
        self.assertIsInstance(result[0], torch.Tensor)
        self.assertEqual(result[0].shape[0], 120)  # no_of_frames
        self.assertEqual(result[0].shape[1], 1080)
        self.assertEqual(result[0].shape[2], 1920)
        self.assertEqual(result[0].shape[3], 3)
        mock_video_capture.assert_called_with("/fake/video1.mp4")
        self.assertEqual(mock_cap_instance.set.call_count, 120)

if __name__ == "__main__":
    unittest.main()
