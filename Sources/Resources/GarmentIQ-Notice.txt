# GarmentIQ integration

Upstream: https://github.com/lygitdata/GarmentIQ
Pinned revision: 6eba6d65f462647b48e9eed24440d609e9e671d6
License: MIT (included alongside this notice).

Architecture: `src/garmentiq/landmark/detection/model_definition.py`, copied unchanged.
Schema: `src/garmentiq/instruction/short sleeve top.json`, copied unchanged.
Weights: https://huggingface.co/lygitdata/garmentiq/resolve/main/hrnet.pth
Weight SHA256: 5b29ada40632cb5ce1aaa38e4896054329c42d0f6c6649a5b9d0b53e41ee04f6
Model repository declares MIT: https://huggingface.co/lygitdata/garmentiq/blob/main/README.md

On You converts the pretrained HRNet to Core ML, keeps its short-sleeved-top output channels, and quantizes weights to signed eight-bit. RGB normalization and quarter-pixel heatmap decoding follow upstream. See `Scripts/convert_garmentiq.py` for reproducible conversion and a landmark equivalence check. The Swift decoder and affine image preparation are adaptations of upstream `landmark/detection/utils.py`.

Apple Vision provides local foreground masking; ARKit provides calibrated metric depth. Neither is part of GarmentIQ. No commercial measurement API, third-party server, or API key is used. We do not ship GarmentIQ's full Python classification/segmentation pipeline or claim support for all garment categories. Garment shape, keypoint confidence, depth confidence, level surface, and consistency across captures are checked before accepting dimensions.

The upstream pretrained model uses DeepFashion landmark conventions. Prediction accuracy on this app's capture flow needs real-garment validation. Conversion equivalence and synthetic geometry tests are not measurement-accuracy certification.
