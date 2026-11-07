"""Convert pinned GarmentIQ HRNet weights to an offline iOS shirt-landmark model.

Run in a Python 3.12 environment with torch==2.7.0, coremltools==9.0,
numpy<2.3 and Pillow. Input: upstream hrnet.pth, output: .mlpackage.
The architecture and landmark schema are vendored with their MIT license.
"""
import hashlib
import importlib.util
from pathlib import Path
import sys
import numpy as np
import torch
import coremltools as ct
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
checkpoint = Path(sys.argv[1])
output = Path(sys.argv[2])
digest = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
assert digest == '5b29ada40632cb5ce1aaa38e4896054329c42d0f6c6649a5b9d0b53e41ee04f6', 'Unexpected upstream checkpoint'
print('Checkpoint SHA256:', digest, flush=True)
spec = importlib.util.spec_from_file_location('garmentiq_model', ROOT / 'Vendor/GarmentIQ/model_definition.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
network = module.PoseHighResolutionNet().eval()
state = torch.load(checkpoint, map_location='cpu', weights_only=True)
if 'state_dict' in state:
    state = state['state_dict']
state = {k.removeprefix('module.'): v for k, v in state.items()}
network.load_state_dict(state, strict=True)
# Preserve exactly the short-sleeved-top channels; remove unused garment heads.
head = torch.nn.Conv2d(48, 25, 1)
head.weight.data.copy_(network.final_layer.weight.data[:25])
head.bias.data.copy_(network.final_layer.bias.data[:25])
network.final_layer = head

class ShirtLandmarks(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.network = network
        self.register_buffer('mean', torch.tensor([.485, .456, .406]).view(1, 3, 1, 1))
        self.register_buffer('std', torch.tensor([.229, .224, .225]).view(1, 3, 1, 1))
    def forward(self, image):
        return self.network((image - self.mean) / self.std)

model = ShirtLandmarks().eval()
torch.set_num_threads(4)
example = torch.rand(1, 3, 384, 288)
traced = torch.jit.trace(model, example)
converted = ct.convert(traced, inputs=[ct.ImageType(name='image', shape=example.shape, scale=1/255)],
                       outputs=[ct.TensorType(name='landmarks')], minimum_deployment_target=ct.target.iOS18,
                       compute_units=ct.ComputeUnit.CPU_ONLY)
config = ct.optimize.coreml.OptimizationConfig(global_config=ct.optimize.coreml.OpLinearQuantizerConfig(mode='linear_symmetric', dtype=np.int8))
compressed = ct.optimize.coreml.linear_quantize_weights(converted, config)
compressed.author = 'Li Yuan, Xinrui Zhai, and Fangzhou Ma (GarmentIQ); Core ML conversion by On You'
compressed.license = 'MIT; see Vendor/GarmentIQ/LICENSE'
compressed.short_description = 'GarmentIQ HRNet: short-sleeved top landmarks, RGB ImageNet normalization, quarter-pixel heatmap decoding.'
compressed.save(str(output))
# Conversion must preserve landmark positions on a real upstream example.
if len(sys.argv) > 3:
    image = Image.open(sys.argv[3]).convert('RGB')
    w, h = image.size
    image = image.transform((288, 384), Image.Transform.AFFINE, (w/288, 0, 0, 0, w/288, h/2 - w*384/576), resample=Image.Resampling.BILINEAR)
    x = torch.from_numpy(np.asarray(image).copy()).permute(2,0,1).unsqueeze(0).float()/255
    with torch.no_grad():
        baseline = model(x).numpy()
    prediction = compressed.predict({'image': image})['landmarks']
    a = baseline.reshape(25, -1).argmax(1)
    b = prediction.reshape(25, -1).argmax(1)
    displacement = np.sqrt((a%72-b%72)**2 + (a//72-b//72)**2)
    print('Heatmap peak displacement:', displacement.tolist(), flush=True)
    assert np.isfinite(prediction).all(), 'Non-finite converted output'
    assert max(displacement[[1,6,11,15,19,24]]) <= 2, 'Conversion shifts a required landmark'
    print('Required landmark conversion check passed.', flush=True)
