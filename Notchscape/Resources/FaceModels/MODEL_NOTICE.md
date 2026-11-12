# SFace model provenance and conversion notice

Original: OpenCV Zoo SFace MobileFaceNet model, contributed by Yaoyao Zhong; the model directory credits Chengrui Wang for the original ONNX conversion. Pinned OpenCV Zoo revision: `48b10fa505aeb51fbd127fc60a5c660040e823b7`.

Official source: https://github.com/opencv/opencv_zoo/tree/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_recognition_sface

The original directory README states that all files in the directory are licensed under Apache License 2.0. Preserve the accompanying original `source/LICENSE` and `source/README.md` attribution with a distributed model.

Modification notice: On 2026-10-29, Notchscape independently converted the unmodified official `face_recognition_sface_2021dec.onnx` through onnx2torch 1.5.15, PyTorch 2.5.1 TorchScript and coremltools 8.3.0 into an FP32 Core ML ML Program with input `face` and output `embedding`. Original internal input normalization is preserved. No Glance or InsightFace code, history or weights were used.

Original ONNX SHA256: `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79` (38,696,353 bytes). Converted package canonical file-list SHA256: `22b0a515abbae2708c1e24981066c94c14441e9d34326f7859cce112d0277c9e`.

Exact source URLs, sizes and hashes are preserved in `source/PROVENANCE.json`. Package hashes, conversion metadata and synthetic parity results are in `ARTIFACT_MANIFEST.json` and `probe/results.json`.

Synthetic conversion parity was measured. Actual face recognition, Vision-derived landmark alignment, similarity thresholds, spoof/replay resistance and unlocking behavior were not validated. RGB head movement is a weak convenience check and does not provide Face ID security.
