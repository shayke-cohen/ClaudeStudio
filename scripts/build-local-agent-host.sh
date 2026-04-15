#!/bin/zsh
set -euo pipefail

if [[ -z "${SRCROOT:-}" || -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "build-local-agent-host.sh requires Xcode build environment variables" >&2
  exit 1
fi

PACKAGE_PATH="$SRCROOT/Packages/OdysseyLocalAgent"
OUTPUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/local-agent/bin"
RUNTIME_OUTPUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/local-agent/runtime"
SWIFT_BIN="$(xcrun --find swift)"
MANAGED_TOOLS_ROOT="${HOME}/.odyssey/local-agent"
MANAGED_RUNNER="${MANAGED_TOOLS_ROOT}/bin/llm-tool"
MANAGED_RUNTIME="${MANAGED_TOOLS_ROOT}/runtime/llm-tool-release"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$RUNTIME_OUTPUT_DIR"

"$SWIFT_BIN" build --package-path "$PACKAGE_PATH" --product OdysseyLocalAgentHost

BIN_DIR="$("$SWIFT_BIN" build --package-path "$PACKAGE_PATH" --product OdysseyLocalAgentHost --show-bin-path)"
HOST_BINARY="$BIN_DIR/OdysseyLocalAgentHost"
if [[ ! -x "$HOST_BINARY" ]]; then
  echo "OdysseyLocalAgentHost binary not found at $HOST_BINARY" >&2
  exit 1
fi

cp "$HOST_BINARY" "$OUTPUT_DIR/OdysseyLocalAgentHost"
chmod +x "$OUTPUT_DIR/OdysseyLocalAgentHost"

# Sign with Hardened Runtime so the binary passes notarization.
# Use the Xcode-provided identity when available, otherwise ad-hoc — Xcode's
# distribution step will re-sign with Developer ID but preserves the runtime flag.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" --options runtime "$OUTPUT_DIR/OdysseyLocalAgentHost"

if [[ -x "$MANAGED_RUNNER" ]]; then
  cp "$MANAGED_RUNNER" "$OUTPUT_DIR/llm-tool"
  chmod +x "$OUTPUT_DIR/llm-tool"
fi

if [[ -d "$MANAGED_RUNTIME" ]]; then
  rm -rf "$RUNTIME_OUTPUT_DIR/llm-tool-release"
  cp -R "$MANAGED_RUNTIME" "$RUNTIME_OUTPUT_DIR/llm-tool-release"
fi
