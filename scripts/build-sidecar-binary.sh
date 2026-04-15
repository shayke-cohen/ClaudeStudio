#!/bin/zsh
set -euo pipefail

if [[ -z "${SRCROOT:-}" || -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "build-sidecar-binary.sh requires Xcode build environment variables" >&2
  exit 1
fi

SIDECAR_SRC="$SRCROOT/sidecar"
OUTPUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
OUTPUT_JS="$OUTPUT_DIR/odyssey-sidecar.js"
OUTPUT_BUN="$OUTPUT_DIR/odyssey-bun"

# Find bun in common install locations
BUN_PATH=""
for candidate in /opt/homebrew/bin/bun /usr/local/bin/bun "$HOME/.bun/bin/bun"; do
  if [[ -x "$candidate" ]]; then
    BUN_PATH="$candidate"
    break
  fi
done

if [[ -z "$BUN_PATH" ]]; then
  echo "build-sidecar-binary.sh: bun not found; skipping sidecar bundle" >&2
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

# Build a single bundled JS file (no compiled runtime — bun binary is bundled separately)
"$BUN_PATH" build --target=bun \
  "$SIDECAR_SRC/src/index.ts" \
  --outfile "$OUTPUT_JS"

echo "build-sidecar-binary.sh: built JS bundle → $OUTPUT_JS"

# Bundle the bun runtime binary (already signed with Hardened Runtime by Oven)
BUN_REAL=$(readlink -f "$BUN_PATH")
cp "$BUN_REAL" "$OUTPUT_BUN"
chmod +x "$OUTPUT_BUN"
echo "build-sidecar-binary.sh: bundled bun runtime → $OUTPUT_BUN"
