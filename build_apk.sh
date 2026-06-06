#!/bin/bash

# Exit immediately if any command fails
set -e

# Define workspace directory
WORKSPACE="/Users/manumathew/Documents/VS_code/DeliMap - the delivery route tracker"
FLUTTER="/Users/manumathew/development/flutter/bin/flutter"

cd "$WORKSPACE"

# Read version from pubspec.yaml
VERSION=$(grep "version: " pubspec.yaml | sed 's/version: //')
DATE_STR=$(date +"%Y%m%d_%H%M%S")
DEFAULT_NAME="delimap_${VERSION//+/_}_$DATE_STR"

# Ask the user for a custom name
if [ -z "$1" ]; then
    echo "--------------------------------------------------------"
    echo "Building DeliMap Release APK..."
    echo "--------------------------------------------------------"
    read -p "Enter a custom name for this APK (default: $DEFAULT_NAME): " CUSTOM_NAME
    if [ -z "$CUSTOM_NAME" ]; then
        CUSTOM_NAME=$DEFAULT_NAME
    fi
else
    CUSTOM_NAME="$1"
fi

# Ensure name ends with .apk
if [[ ! "$CUSTOM_NAME" == *.apk ]]; then
    CUSTOM_NAME="${CUSTOM_NAME}.apk"
fi

echo ""
echo "Building release APK..."
"$FLUTTER" build apk --release

# Ensure apks directory exists
mkdir -p apks

# Copy and rename APK
cp build/app/outputs/flutter-apk/app-release.apk "apks/$CUSTOM_NAME"

echo ""
echo "========================================================"
echo "✅ Build Complete!"
echo "Saved separately as: $WORKSPACE/apks/$CUSTOM_NAME"
echo "========================================================"
