from flask import Flask, request, jsonify
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.transforms as transforms
from PIL import Image
import numpy as np
import cv2
import os
import json

app = Flask(__name__)

# Global training input size
input_size = 128

# -------------------------
# Define the CNN architecture
# -------------------------
class SimpleCNN(nn.Module):
    def __init__(self):
        super(SimpleCNN, self).__init__()
        self.conv1 = nn.Conv2d(3, 16, kernel_size=3, padding=1)
        self.conv2 = nn.Conv2d(16, 32, kernel_size=3, padding=1)
        self.conv3 = nn.Conv2d(32, 64, kernel_size=3, padding=1)
        self.pool = nn.MaxPool2d(2, 2)
        self.dropout = nn.Dropout(0.5)
        # Flattened size = 64 * (input_size/8) * (input_size/8)
        self.fc1 = nn.Linear(64 * (input_size // 8) * (input_size // 8), 128)
        self.fc2 = nn.Linear(128, 2)  # two classes: "ai" and "human"

    def forward(self, x):
        x = self.pool(F.relu(self.conv1(x)))  # shape: [B, 16, input_size/2, input_size/2]
        x = self.pool(F.relu(self.conv2(x)))  # shape: [B, 32, input_size/4, input_size/4]
        x = self.pool(F.relu(self.conv3(x)))  # shape: [B, 64, input_size/8, input_size/8]
        x = x.view(x.size(0), -1)
        x = self.dropout(F.relu(self.fc1(x)))
        x = self.fc2(x)
        return x

# -------------------------
# Define the GradCAM class
# -------------------------
class GradCAM:
    def __init__(self, model, target_layer):
        self.model = model
        self.target_layer = target_layer
        self.gradients = None
        self.activations = None
        self.hook_handles = []
        self._register_hooks()

    def _register_hooks(self):
        def forward_hook(module, input, output):
            self.activations = output.detach()

        def backward_hook(module, grad_input, grad_output):
            self.gradients = grad_output[0].detach()

        handle_forward = self.target_layer.register_forward_hook(forward_hook)
        handle_backward = self.target_layer.register_full_backward_hook(backward_hook)
        self.hook_handles.extend([handle_forward, handle_backward])

    def __call__(self, input_tensor, target_class=None):
        self.model.eval()
        output = self.model(input_tensor)
        if target_class is None:
            target_class = output.argmax(dim=1).item()

        one_hot = torch.zeros_like(output)
        one_hot[0, target_class] = 1

        self.model.zero_grad()
        output.backward(gradient=one_hot, retain_graph=True)

        weights = torch.mean(self.gradients, dim=(2, 3), keepdim=True)
        grad_cam_map = torch.sum(weights * self.activations, dim=1, keepdim=True)
        grad_cam_map = F.relu(grad_cam_map)

        # Normalize the map
        grad_cam_map = grad_cam_map - grad_cam_map.min()
        grad_cam_map = grad_cam_map / (grad_cam_map.max() + 1e-8)
        grad_cam_map = grad_cam_map.squeeze().cpu().numpy()
        return output, grad_cam_map

    def remove_hooks(self):
        for handle in self.hook_handles:
            handle.remove()

# -------------------------
# Utility: overlay heatmap on image
# -------------------------
def get_heatmap_on_image(original_image, heatmap, alpha=0.4):
    original_image = np.array(original_image)
    heatmap = cv2.resize(heatmap, (original_image.shape[1], original_image.shape[0]))
    heatmap = np.uint8(255 * heatmap)
    heatmap = cv2.applyColorMap(heatmap, cv2.COLORMAP_JET)
    heatmap = cv2.cvtColor(heatmap, cv2.COLOR_BGR2RGB)
    overlayed = cv2.addWeighted(original_image, 1 - alpha, heatmap, alpha, 0)
    return overlayed

# -------------------------
# Load model and define transform
# -------------------------
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = SimpleCNN().to(device)
model.load_state_dict(torch.load("model.pth", map_location=device))
model.eval()

transform = transforms.Compose([
    transforms.Resize((input_size, input_size)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.5, 0.5, 0.5],
                         std=[0.5, 0.5, 0.5])
])

# Class mapping: 0 -> "ai", 1 -> "human"
classes = {0: "ai", 1: "human"}

# -------------------------
# Function that processes the image and runs GradCAM
# -------------------------
def process_image(image_path):
    image_path = os.path.join('..', image_path)
    original_image = Image.open(image_path).convert("RGB")
    input_tensor = transform(original_image).unsqueeze(0).to(device)

    # Get prediction from the model
    with torch.no_grad():
        output = model(input_tensor)
    predicted_class = torch.argmax(output, dim=1).item()

    # Run GradCAM on the last conv layer (conv3)
    gradcam = GradCAM(model, model.conv3)
    _, cam_map = gradcam(input_tensor, target_class=predicted_class)
    gradcam.remove_hooks()

    # Generate the GradCAM heatmap overlay
    overlayed_image = get_heatmap_on_image(original_image, cam_map)

    # Save the output image
    output_dir = 'output'
    file_class = image_path.split("/")[-2]
    file_name = image_path.split("/")[-1]
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    output_filename = f"{file_class}_{file_name}"
    output_filepath = os.path.join(output_dir, output_filename)
    cv2.imwrite(output_filepath, cv2.cvtColor(overlayed_image, cv2.COLOR_RGB2BGR))

    return classes.get(predicted_class, "Unknown"), output_filepath

# -------------------------
# Flask endpoint definition
# -------------------------
@app.route('/flask-api/gradcam', methods=['GET'])
def gradcam_endpoint():
    # query param: image_url (e.g. images/human/50.jpg)
    image_url = request.args.get('image_url')
    if not image_url:
        return jsonify({"error": "Missing 'image_url' parameter"}), 400
    try:
        classification, output_image = process_image(image_url)
        return jsonify({
            "classification": classification,
            "gradcam_image": output_image
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/flask-api/clear', methods=['DELETE'])
def clear():
    output_dir = 'output'
    if os.path.exists(output_dir):
        try:
            for filename in os.listdir(output_dir):
                file_path = os.path.join(output_dir, filename)
                if os.path.isfile(file_path) or os.path.islink(file_path):
                    os.unlink(file_path)
            return jsonify({"message": "Output directory cleared"}), 200
        except Exception as e:
            return jsonify({"error": f"Error clearing output directory: {str(e)}"}), 500
    else:
        return jsonify({"message": "Output directory does not exist"}), 200

@app.route('/flask-api/device-data', methods=['POST'])
def store_device_data():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Missing JSON data"}), 400

        output_file = "device_data.jsonl"
        with open(output_file, "a") as f:
            f.write(f"{json.dumps(data)}\n")

        return jsonify({"message": "Device data stored successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, port=9000)
