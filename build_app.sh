#!/bin/zsh
set -eu
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD_ROOT="${EQUAL_AGENTS_BUILD_ROOT:-$ROOT/../../work/build}"
APP="${EQUAL_AGENTS_APP_OUTPUT:-$ROOT/../Equal Agents.app}"
NODE="${EQUAL_AGENTS_BUNDLE_NODE:-$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node}"
if [[ ! -x "$NODE" ]]; then
  echo 'Set EQUAL_AGENTS_BUNDLE_NODE to a standalone Node.js 22+ binary.' >&2
  exit 1
fi
mkdir -p "$BUILD_ROOT/modules" "$BUILD_ROOT/cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/modules"
export SWIFT_MODULECACHE_PATH="$BUILD_ROOT/modules"
if [[ -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
swift build --disable-sandbox --cache-path "$BUILD_ROOT/cache" --scratch-path "$BUILD_ROOT/spm" -c release -j 2
BIN="$(swift build --disable-sandbox --cache-path "$BUILD_ROOT/cache" --scratch-path "$BUILD_ROOT/spm" -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$BIN/EqualAgents" "$APP/Contents/MacOS/EqualAgents"
cp engine/*.mjs engine/*.ts "$APP/Contents/Resources/engine/"
cp "$NODE" "$APP/Contents/Resources/node"
if [[ ! -s Resources/Node-LICENSE.txt ]]; then echo 'Node license file is missing or empty.' >&2; exit 1; fi
cp Resources/Node-LICENSE.txt "$APP/Contents/Resources/Node-LICENSE.txt"
if [[ -f Resources/EqualAgents.icns ]]; then cp Resources/EqualAgents.icns "$APP/Contents/Resources/"; fi
python3 - "$APP" <<'PY'
import plistlib, pathlib, sys
app = pathlib.Path(sys.argv[1])
info = {'CFBundleName':'Equal Agents', 'CFBundleDisplayName':'Equal Agents', 'CFBundleIdentifier':'com.niqi.equalagents',
        'CFBundleVersion':'1', 'CFBundleShortVersionString':'0.1.0', 'CFBundlePackageType':'APPL',
        'CFBundleExecutable':'EqualAgents', 'CFBundleIconFile':'EqualAgents', 'LSMinimumSystemVersion':'14.0',
        'NSHighResolutionCapable':True, 'CFBundleDevelopmentRegion':'en', 'CFBundleLocalizations':['en'],
        'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$APP/Contents/Resources/node"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
