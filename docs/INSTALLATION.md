# Installation Guide

## Prerequisites

- **Godot 4.3+** with export templates installed for your exact version
- Java JDK 17
- Android SDK (with SDK 24+ and build tools 34)
- An Android device or emulator with an MWA-compatible wallet (Phantom, Solflare, etc.)

> **Important:** The `godot-lib.aar`, Android build template, and export templates must all match your exact Godot version. Mixing versions (e.g., 4.6 templates with 4.7 editor) will cause `Android build version mismatch` errors.

## Automated Setup (Recommended)

Run the setup script from the project root:

```bash
./setup.sh
```

This handles steps 3–4 automatically:
- Installs the Android build template from your export templates
- Extracts `godot-lib.aar` matching your Godot version
- Builds the Kotlin plugin
- Copies the AAR and `.gdap` manifest to `android/plugins/`
- Generates a debug keystore if you don't have one

After running the script, skip to [Step 5: Configure Android Export](#5-configure-android-export).

You can set `GODOT_BIN` if your Godot binary isn't named `godot`:

```bash
GODOT_BIN=/path/to/godot ./setup.sh
```

## Manual Setup

### 1. Add the Plugin

Copy the `addons/solana_mwa/` folder into your Godot project's `addons/` directory.

```
your_project/
  addons/
    solana_mwa/
      scripts/
        mobile_wallet_adapter.gd
        mwa_types.gd
        mwa_cache.gd
        mwa_file_cache.gd
        mwa_autoload.gd
      plugin.gd
      plugin.cfg
```

### 2. Enable the Plugin

1. Open your project in Godot
2. Go to **Project > Project Settings > Plugins**
3. Enable **Solana MWA SDK**

This registers the `MWA` autoload singleton, giving you global access via `MWA.adapter`.

### 3. Install Android Build Template

**Option A (Godot UI):** Go to **Project > Install Android Build Template...** This creates the `android/build/` directory with files matching your Godot version.

**Option B (CLI):** Extract manually from your export templates:

```bash
# Find your templates directory:
#   macOS: ~/Library/Application Support/Godot/export_templates/<version>/
#   Linux: ~/.local/share/godot/export_templates/<version>/
#   Windows: %APPDATA%/Godot/export_templates/<version>/

unzip "<templates_dir>/android_source.zip" -d android/build/
```

After extracting, create the version marker so Godot recognizes the template:

```bash
# Replace with your exact Godot version (run: godot --version)
echo -n "4.6.1.stable" > android/.build_version
```

> **Do this BEFORE building the plugin.** The build template must exist first.

### 4. Build the Android Plugin

The SDK requires an Android plugin (`.aar`) that bridges GDScript to the native MWA protocol.

#### a. Get `godot-lib.aar`

You need `godot-lib.template_release.aar` from the export templates **for your exact Godot version**.

**Option 1:** Extract from your installed templates:
```bash
mkdir -p android/plugin/libs
# Find your templates directory:
#   macOS: ~/Library/Application Support/Godot/export_templates/<version>/
#   Linux: ~/.local/share/godot/export_templates/<version>/
#   Windows: %APPDATA%/Godot/export_templates/<version>/

# Extract from android_source.zip:
unzip "<templates_dir>/android_source.zip" "libs/release/godot-lib.template_release.aar" -d /tmp/godot-extract
cp /tmp/godot-extract/libs/release/godot-lib.template_release.aar android/plugin/libs/
```

**Option 2:** Download from the [Godot downloads archive](https://godotengine.org/download/archive/):
```bash
mkdir -p android/plugin/libs
# Download the .tpz for your version, then:
unzip Godot_v4.x_export_templates.tpz templates/android_source.zip -d /tmp/godot-tpz
unzip /tmp/godot-tpz/templates/android_source.zip "libs/release/godot-lib.template_release.aar" -d /tmp/godot-extract
cp /tmp/godot-extract/libs/release/godot-lib.template_release.aar android/plugin/libs/
```

#### b. Build the AAR

```bash
cd android/
chmod +x gradlew
./gradlew :plugin:assembleRelease
```

The output AAR will be at `android/plugin/build/outputs/aar/plugin-release.aar`.

#### c. Install the Plugin

Copy the AAR and `.gdap` manifest to your project's `android/plugins/` directory:

```bash
mkdir -p android/plugins
cp android/plugin/build/outputs/aar/plugin-release.aar android/plugins/SolanaMWA.aar
```

Create `android/plugins/SolanaMWA.gdap`:

```ini
[config]

name="SolanaMWA"
binary_type="local"
binary="SolanaMWA.aar"

[dependencies]

local=[]
remote=["com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.3", "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3", "androidx.activity:activity-ktx:1.8.2", "androidx.lifecycle:lifecycle-runtime-ktx:2.7.0"]
```

### 5. Configure Android Export

1. Go to **Project > Export** and add an **Android** export preset
2. Enable **Use Gradle Build**
3. Under **Plugins**, enable **SolanaMWA**
4. Set **Min SDK** to **24** (Android 7.0)
5. Set **Target SDK** to **34**
6. Under **Permissions**, add `android.permission.INTERNET`
7. Under **Architectures**, enable **arm64-v8a** (for devices) or **x86_64** (for emulators)
8. Under **Keystore > Debug**, set the path to your debug keystore:
   - Default location: `~/.android/debug.keystore`
   - User: `androiddebugkey`
   - Password: `android`
   - If you don't have one, generate it: `keytool -genkey -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`

### 6. Install a Wallet

Install an MWA-compatible wallet on your Android device or emulator:
- [Phantom](https://phantom.app/)
- [Solflare](https://solflare.com/)

### 7. Set Rendering Mode (Optional)

If testing on an emulator, the project already defaults to OpenGL compatibility mode. If you changed it, set it back in `project.godot`:

```ini
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

Vulkan may not work on some emulators.

## Quick Start

```gdscript
extends Node

func _ready():
    var adapter = MWA.adapter
    adapter.identity = MWATypes.DappIdentity.new("My App", "https://myapp.com", "icon.png")
    adapter.cluster = MWATypes.Cluster.MAINNET
    adapter.authorized.connect(_on_authorized)
    adapter.authorization_failed.connect(_on_auth_failed)
    adapter.authorize()

func _on_authorized(result):
    print("Connected! Account: ", result.accounts[0].address)

func _on_auth_failed(error_code: int, error_message: String):
    print("Auth failed: ", error_message)
```

## Troubleshooting

### "Android build version mismatch"

This is the most common setup issue. It means one of these doesn't match your Godot editor version:

1. **Export templates** — Go to **Editor > Manage Export Templates** and install templates for your exact version
2. **Android build template** — Delete `android/build/` and `android/.build_version`, then reinstall (Project > Install Android Build Template, or re-run `./setup.sh`)
3. **godot-lib.aar** — Re-extract from the export templates matching your version (Step 4a above)

All three must be the same version as your Godot editor (e.g., all 4.6.1.stable).

### "Connecting..." hangs forever
- Make sure an MWA-compatible wallet (Phantom/Solflare) is installed on the device
- Ensure the wallet has been set up with at least one account
- Check that the cluster (Devnet/Mainnet/Testnet) matches your wallet's network

### Black screen on emulator
- Switch rendering to `gl_compatibility` mode (Vulkan is not well supported on emulators)

### "Activity is not a ComponentActivity"
- Make sure you are using the Gradle build (not the default export). The `ActivityResultSender` requires `ComponentActivity`.

### Build errors with Kotlin version mismatch
- Ensure the Kotlin version in `android/build.gradle.kts` matches the one used by your Godot version's `godot-lib.aar`. For Godot 4.6+, use Kotlin 2.1.0.

### Sign/Send transactions fail with "null"
- The example app sends dummy random bytes, not valid Solana transactions. In a real app, build proper Solana transaction bytes.

### Authorization request failed
- The auth token from a previous session may have expired. Clear the cache and reconnect.
- Make sure the cluster matches your wallet's network (e.g., Mainnet wallet won't work with Devnet cluster).

### No debug keystore / signing errors
- Generate one: `keytool -genkey -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`
- Make sure the export preset points to the correct keystore path.
