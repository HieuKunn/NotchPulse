#!/usr/bin/env python3
import os
import sys

def main():
    print("NotchPulse - Liveness Model Setup")
    print("=================================")
    print("This script requires 'coremltools' and 'torch'.")
    print("If you haven't installed them, run: pip3 install coremltools torch\n")
    
    try:
        import coremltools as ct
        import torch
        import torch.nn as nn
    except ImportError:
        print("Error: Missing required packages. Please install them using pip.")
        sys.exit(1)

    print("Generating a Mock Liveness Model (MiniFASNet placeholder)...")
    print("Note: In production, you should replace this with a real trained ONNX/PyTorch model.")

    # Create a simple mock PyTorch model that matches MiniFASNet signature
    class MockMiniFASNet(nn.Module):
        def __init__(self):
            super(MockMiniFASNet, self).__init__()
            # Just some dummy layers to make the model valid
            self.conv = nn.Conv2d(3, 16, kernel_size=3, stride=2, padding=1)
            self.fc = nn.Linear(16 * 40 * 40, 3) # Output: 3 classes (0: fake, 1: fake, 2: live)

        def forward(self, x):
            x = self.conv(x)
            x = x.view(x.size(0), -1)
            x = self.fc(x)
            # Simulate a "Live" prediction for testing purposes
            # (Class 0, 1 = Spoof, Class 2 = Live in some MiniFAS implementations)
            # But normally we just want a scalar output. Let's output a 3-element tensor
            return x

    model = MockMiniFASNet()
    model.eval()

    # Trace the model
    dummy_input = torch.randn(1, 3, 80, 80)
    traced_model = torch.jit.trace(model, dummy_input)

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="input", shape=(1, 3, 80, 80))],
        outputs=[ct.TensorType(name="output")],
        minimum_deployment_target=ct.target.macOS13
    )

    # Add metadata
    mlmodel.author = "NotchPulse"
    mlmodel.license = "MIT"
    mlmodel.short_description = "Mock MiniFASNet Liveness Detection Model"

    output_path = "../NotchPulse/Resources/Liveness.mlpackage"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    mlmodel.save(output_path)
    print(f"\n✅ Successfully generated mock Liveness model at: {output_path}")
    print("   You can now build and run NotchPulse to test the pipeline.")

if __name__ == "__main__":
    main()
