#!/usr/bin/env bash
# Godot MWA SDK - Automated Setup Script
# Prepares the project for Android export from a fresh clone.
#
# Usage: ./setup.sh
#
# Prerequisites:
#   - Godot 4.3+ (with 'godot' in PATH or set GODOT_BIN)
#   - Java JDK 17
#   - Android SDK (ANDROID_HOME set)
#   - Android export templates installed for your Godot version

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Godot MWA SDK Setup ==="
echo ""

# --- Check prerequisites ---

echo "[1/7] Checking prerequisites..."

if ! command -v "$GODOT_BIN" &>/dev/null; then
    echo "ERROR: Godot not found. Install Godot 4.3+ and add to PATH, or set GODOT_BIN."
    exit 1
fi

GODOT_VERSION=$("$GODOT_BIN" --version 2>&1 | head -1)
echo "  Godot: $GODOT_VERSION"

# Extract version string (e.g., "4.6.1.stable" from "4.6.1.stable.official.abc123")
GODOT_VER_SHORT=$(echo "$GODOT_VERSION" | sed 's/\.official.*//')
echo "  Version tag: $GODOT_VER_SHORT"

if ! java -version &>/dev/null 2>&1; then
    echo "ERROR: Java not found. Install JDK 17."
    exit 1
fi
echo "  Java: $(java -version 2>&1 | head -1)"

if [ -z "${ANDROID_HOME:-}" ]; then
    # Try common default locations
    if [ -d "$HOME/Library/Android/sdk" ]; then
        export ANDROID_HOME="$HOME/Library/Android/sdk"
    elif [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_HOME="$HOME/Android/Sdk"
    else
        echo "ERROR: ANDROID_HOME not set and Android SDK not found in default locations."
        exit 1
    fi
fi
echo "  Android SDK: $ANDROID_HOME"

# --- Locate export templates ---

echo ""
echo "[2/7] Locating Godot export templates..."

case "$(uname)" in
    Darwin)  TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VER_SHORT" ;;
    Linux)   TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_VER_SHORT" ;;
    *)       TEMPLATES_DIR="$APPDATA/Godot/export_templates/$GODOT_VER_SHORT" ;;
esac

if [ ! -d "$TEMPLATES_DIR" ]; then
    echo "ERROR: Export templates not found at: $TEMPLATES_DIR"
    echo "Install them via: Editor > Manage Export Templates > Download and Install"
    exit 1
fi
echo "  Found: $TEMPLATES_DIR"

if [ ! -f "$TEMPLATES_DIR/android_source.zip" ]; then
    echo "ERROR: android_source.zip not found in export templates."
    exit 1
fi

# --- Install Android build template ---

echo ""
echo "[3/7] Installing Android build template..."

if [ -d "$PROJECT_DIR/android/build" ]; then
    echo "  android/build/ already exists, skipping. Delete it to reinstall."
else
    unzip -q "$TEMPLATES_DIR/android_source.zip" -d "$PROJECT_DIR/android/build/"
    echo "  Extracted to android/build/"
fi

# Create .build_version so Godot recognizes the template
echo -n "$GODOT_VER_SHORT" > "$PROJECT_DIR/android/.build_version"
echo "  Created android/.build_version ($GODOT_VER_SHORT)"

# --- Extract godot-lib.aar ---

echo ""
echo "[4/7] Extracting godot-lib.aar..."

GODOT_LIB_DIR="$PROJECT_DIR/android/plugin/libs"
mkdir -p "$GODOT_LIB_DIR"

if [ -f "$GODOT_LIB_DIR/godot-lib.template_release.aar" ]; then
    echo "  godot-lib.aar already exists, skipping. Delete it to re-extract."
else
    TMP_DIR=$(mktemp -d)
    unzip -q "$TEMPLATES_DIR/android_source.zip" "libs/release/godot-lib.template_release.aar" -d "$TMP_DIR"
    cp "$TMP_DIR/libs/release/godot-lib.template_release.aar" "$GODOT_LIB_DIR/"
    rm -rf "$TMP_DIR"
    echo "  Extracted godot-lib.template_release.aar"
fi

# --- Build the Kotlin plugin ---

echo ""
echo "[5/7] Building Android plugin..."

cd "$PROJECT_DIR/android"
chmod +x gradlew
./gradlew :plugin:assembleRelease --quiet
echo "  Plugin built successfully."

# --- Install plugin AAR + manifest ---

echo ""
echo "[6/7] Installing plugin to android/plugins/..."

mkdir -p "$PROJECT_DIR/android/plugins"
cp "$PROJECT_DIR/android/plugin/build/outputs/aar/plugin-release.aar" "$PROJECT_DIR/android/plugins/SolanaMWA.aar"

cat > "$PROJECT_DIR/android/plugins/SolanaMWA.gdap" << 'GDAP'
[config]

name="SolanaMWA"
binary_type="local"
binary="SolanaMWA.aar"

[dependencies]

local=[]
remote=["com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.3", "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3", "androidx.activity:activity-ktx:1.8.2", "androidx.lifecycle:lifecycle-runtime-ktx:2.7.0"]
GDAP

echo "  Installed SolanaMWA.aar + SolanaMWA.gdap"

# --- Generate debug keystore if missing ---

echo ""
echo "[7/7] Checking debug keystore..."

KEYSTORE_PATH="$HOME/.android/debug.keystore"
if [ -f "$KEYSTORE_PATH" ]; then
    echo "  Debug keystore exists at $KEYSTORE_PATH"
else
    mkdir -p "$HOME/.android"
    keytool -genkey -v -keystore "$KEYSTORE_PATH" \
        -storepass android -alias androiddebugkey -keypass android \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
    echo "  Generated debug keystore at $KEYSTORE_PATH"
fi

# --- Done ---

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Open the project in Godot: godot --editor"
echo "  2. Go to Project > Export, add an Android preset with these settings:"
echo "     - Use Gradle Build: ON"
echo "     - Plugins > SolanaMWA: ON"
echo "     - Min SDK: 24"
echo "     - Target SDK: 34"
echo "     - Architectures: arm64-v8a (for device) or x86_64 (for emulator)"
echo "     - Keystore Debug: $KEYSTORE_PATH"
echo "     - Keystore Debug User: androiddebugkey"
echo "     - Keystore Debug Password: android"
echo "  3. Export and run on an Android device/emulator with a wallet (Phantom, Solflare)"
echo ""
echo "Or export from CLI after configuring export_presets.cfg:"
echo "  godot --headless --export-debug \"Android\" output.apk"
