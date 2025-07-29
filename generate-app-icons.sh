#!/bin/bash

# Generate app icons from SVG for macOS
# Requires rsvg-convert (install with: brew install librsvg)

SVG_FILE="holidu-logo.svg"
ICON_DIR="litellm-oidc-proxy/Assets.xcassets/AppIcon.appiconset"

# Check if rsvg-convert is installed
if ! command -v rsvg-convert &> /dev/null; then
    echo "rsvg-convert is not installed. Installing with Homebrew..."
    brew install librsvg
fi

# Create icon sizes needed for macOS
echo "Generating app icons..."

# 16x16@1x
rsvg-convert -w 16 -h 16 "$SVG_FILE" -o "$ICON_DIR/icon_16x16.png"

# 16x16@2x (32x32)
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICON_DIR/icon_16x16@2x.png"

# 32x32@1x
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICON_DIR/icon_32x32.png"

# 32x32@2x (64x64)
rsvg-convert -w 64 -h 64 "$SVG_FILE" -o "$ICON_DIR/icon_32x32@2x.png"

# 128x128@1x
rsvg-convert -w 128 -h 128 "$SVG_FILE" -o "$ICON_DIR/icon_128x128.png"

# 128x128@2x (256x256)
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICON_DIR/icon_128x128@2x.png"

# 256x256@1x
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICON_DIR/icon_256x256.png"

# 256x256@2x (512x512)
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICON_DIR/icon_256x256@2x.png"

# 512x512@1x
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICON_DIR/icon_512x512.png"

# 512x512@2x (1024x1024)
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$ICON_DIR/icon_512x512@2x.png"

echo "App icons generated successfully!"