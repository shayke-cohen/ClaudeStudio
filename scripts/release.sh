#!/bin/zsh
set -euo pipefail

# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.2.0

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g. 0.2.0)}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Version must be in semver format X.Y.Z (got: $VERSION)" >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/distribution"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_PATH="$TEMP_DIR/Odyssey.xcarchive"
EXPORT_DIR="$TEMP_DIR/export"
APP_PATH="$EXPORT_DIR/Odyssey.app"
ZIP_PATH="$TEMP_DIR/Odyssey-notarize.zip"
DMG_NAME="Odyssey-${VERSION}.dmg"
DMG_PATH="$TEMP_DIR/$DMG_NAME"

# ── Step 1: Validate prerequisites ──────────────────────────────────────────

echo "==> Validating prerequisites..."

for tool in xcodegen create-dmg gh xcrun plutil; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' not found. Install via Homebrew: brew install $tool" >&2
    exit 1
  fi
done

SIGN_UPDATE="${SIGN_UPDATE_PATH:?ERROR: Set SIGN_UPDATE_PATH to the path of ~/tools/sparkle/sign_update}"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not executable at $SIGN_UPDATE" >&2
  exit 1
fi

echo "    Prerequisites OK."

plutil -lint "$DIST_DIR/ExportOptions.plist" > /dev/null || {
  echo "ERROR: $DIST_DIR/ExportOptions.plist is invalid" >&2
  exit 1
}

# ── Step 2: Bump version ────────────────────────────────────────────────────

echo "==> Bumping version to $VERSION..."
cd "$REPO_ROOT"

# Bump MARKETING_VERSION in project.yml
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml

# Auto-increment CURRENT_PROJECT_VERSION (Sparkle uses this for update ordering)
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*CURRENT_PROJECT_VERSION: //' | tr -d ' ')
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Could not parse CURRENT_PROJECT_VERSION from project.yml" >&2
  exit 1
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}$/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

echo "    Version: $VERSION  |  Build: $CURRENT_BUILD → $NEW_BUILD"

# Generate release notes from commits since last version bump
PREV_BUMP=$(git log --oneline --no-merges | grep "chore: bump to v" | head -2 | tail -1 | awk '{print $1}')
RELEASE_NOTES_MD=""
RELEASE_NOTES_HTML="<ul>"
while IFS= read -r line; do
  msg=$(echo "$line" | sed 's/^[a-f0-9]* //')
  # Skip chore/docs/test/perf internals — keep feat and fix
  if echo "$msg" | grep -qE '^(feat|fix)\(?(.*)\)?:'; then
    clean=$(echo "$msg" | sed 's/^feat[^:]*: //' | sed 's/^fix[^:]*: //')
    RELEASE_NOTES_MD+="- ${clean}"$'\n'
    RELEASE_NOTES_HTML+="<li>${clean}</li>"
  fi
done < <(git log ${PREV_BUMP}..HEAD --oneline --no-merges 2>/dev/null || true)
RELEASE_NOTES_HTML+="</ul>"

if [[ -z "$RELEASE_NOTES_MD" ]]; then
  RELEASE_NOTES_MD="- Minor fixes and improvements"
  RELEASE_NOTES_HTML="<ul><li>Minor fixes and improvements</li></ul>"
fi

echo "    Release notes:"
echo "$RELEASE_NOTES_MD" | sed 's/^/      /'

xcodegen generate
echo "    Xcode project regenerated."

# ── Step 3: Archive ─────────────────────────────────────────────────────────

echo "==> Archiving (this takes a few minutes)..."
xcodebuild archive \
  -scheme Odyssey \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=U6BSY4N9E3 \
  2>&1 | grep -E "(error:|warning: 'Odyssey'|ARCHIVE SUCCEEDED|ARCHIVE FAILED)" | tail -10 || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "ERROR: Archive not found at $ARCHIVE_PATH — xcodebuild archive failed." >&2
  exit 1
fi
echo "    Archive OK: $ARCHIVE_PATH"

# ── Step 4: Export with Developer ID ────────────────────────────────────────

echo "==> Exporting with Developer ID..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$DIST_DIR/ExportOptions.plist" \
  2>&1 | grep -E "(error:|EXPORT SUCCEEDED|EXPORT FAILED)" | tail -5 || true

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Exported app not found at $APP_PATH" >&2
  exit 1
fi
echo "    Export OK: $APP_PATH"

# ── Step 5: Notarize ────────────────────────────────────────────────────────

echo "==> Notarizing (submitting to Apple — may take a few minutes)..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Prefer explicit env-var credentials (reliable in background/CI); fall back to keychain profile.
if [[ -n "${NOTARIZE_APPLE_ID:-}" && -n "${NOTARIZE_TEAM_ID:-}" && -n "${NOTARIZE_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --team-id "$NOTARIZE_TEAM_ID" \
    --password "$NOTARIZE_PASSWORD" \
    --wait
else
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile odyssey-notarize \
    --wait
fi

echo "    Notarization OK."

# ── Step 6: Staple ──────────────────────────────────────────────────────────

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "    Staple OK."

# ── Step 7: Create DMG ──────────────────────────────────────────────────────

echo "==> Creating DMG..."
# Detect Developer ID identity — use SHA-1 hash to avoid ambiguity when multiple
# certs share the same name (e.g. renewed Developer ID certs in the same Keychain).
# Among all matching certs, pick the one with the latest expiry.
CODESIGN_IDENTITY=""
_best_expiry_epoch=0
while IFS= read -r _sha; do
  _pem=$(security find-certificate -c "Developer ID Application" -p -Z -a \
    ~/Library/Keychains/login.keychain-db 2>/dev/null \
    | awk "/SHA-1 hash: $_sha/{f=1} f && /BEGIN CERTIFICATE/{p=1} p{print} p && /END CERTIFICATE/{exit}")
  _expiry=$(echo "$_pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  _epoch=$(date -j -f "%b %d %T %Y %Z" "$_expiry" "+%s" 2>/dev/null || echo 0)
  if (( _epoch > _best_expiry_epoch )); then
    _best_expiry_epoch=$_epoch
    CODESIGN_IDENTITY="$_sha"
  fi
done < <(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | awk '{print $2}')

CREATE_DMG_ARGS=(
  --volname "Odyssey $VERSION"
  --window-pos 200 120
  --window-size 540 380
  --icon-size 128
  --icon "Odyssey.app" 140 180
  --hide-extension "Odyssey.app"
  --app-drop-link 400 180
)

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  CREATE_DMG_ARGS+=(--codesign "$CODESIGN_IDENTITY")
  CERT_NAME=$(security find-identity -v -p codesigning 2>/dev/null | grep "$CODESIGN_IDENTITY" | sed 's/.*"\(.*\)".*/\1/')
  echo "    Signing DMG as: $CERT_NAME [$CODESIGN_IDENTITY]"
fi

create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$EXPORT_DIR/"

if [[ ! -f "$DMG_PATH" ]] || [[ ! -s "$DMG_PATH" ]]; then
  echo "ERROR: DMG not created at $DMG_PATH" >&2
  exit 1
fi
echo "    DMG OK: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── Step 8: Sparkle-sign DMG ────────────────────────────────────────────────

echo "==> Signing DMG for Sparkle..."
# sign_update outputs a line like:
#   sparkle:edSignature="BASE64SIG" length="BYTES"
# Uses Keychain by default (generate_keys saves there); pass --ed-key-file if
# SPARKLE_PRIVATE_KEY_PATH is set (for file-based key storage).
SIGN_UPDATE_ARGS=("$DMG_PATH")
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
  SIGN_UPDATE_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_PATH")
fi
SIG_OUTPUT=$("$SIGN_UPDATE" "${SIGN_UPDATE_ARGS[@]}" 2>&1)
ED_SIGNATURE=$(echo "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
DMG_LENGTH=$(echo "$SIG_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

# Fallback: compute length ourselves if sign_update didn't output it
if [[ -z "$DMG_LENGTH" ]]; then
  DMG_LENGTH=$(wc -c < "$DMG_PATH" | tr -d ' ')
fi

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "ERROR: Could not extract EdDSA signature from sign_update output:" >&2
  echo "$SIG_OUTPUT" >&2
  exit 1
fi

echo "    EdDSA signature: ${ED_SIGNATURE:0:20}..."
echo "    DMG length: $DMG_LENGTH bytes"

# ── Step 9: GitHub Release ──────────────────────────────────────────────────

echo "==> Creating GitHub release v$VERSION..."
gh release create "v${VERSION}" "$DMG_PATH" \
  --repo shayke-cohen/Odyssey-releases \
  --title "Odyssey v${VERSION}" \
  --notes "$RELEASE_NOTES_MD"

DMG_URL="https://github.com/shayke-cohen/Odyssey-releases/releases/download/v${VERSION}/${DMG_NAME}"
echo "    GitHub release OK: $DMG_URL"

# ── Step 10: Update appcast.xml ─────────────────────────────────────────────

echo "==> Updating appcast.xml..."
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

RELEASES_REPO_DIR="$TEMP_DIR/Odyssey-releases"
git clone https://github.com/shayke-cohen/Odyssey-releases.git "$RELEASES_REPO_DIR" --quiet
APPCAST="$RELEASES_REPO_DIR/appcast.xml"

python3 - "$APPCAST" "$VERSION" "$NEW_BUILD" "$PUB_DATE" "$DMG_URL" "$ED_SIGNATURE" "$DMG_LENGTH" "$RELEASE_NOTES_HTML" << 'PYEOF'
import sys, re
import xml.etree.ElementTree as ET

appcast_path, version, build, pub_date, dmg_url, ed_sig, dmg_len, notes_html = sys.argv[1:]

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

tree = ET.parse(appcast_path)
root = tree.getroot()
channel = root.find("channel")

item = ET.Element("item")
ET.SubElement(item, "title").text = f"Version {version}"
ET.SubElement(item, "pubDate").text = pub_date
ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build
ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
# Release notes shown in Sparkle update dialog
ET.SubElement(item, "description").text = f"CDATA_PLACEHOLDER_{version}"
enc = ET.SubElement(item, "enclosure")
enc.set("url", dmg_url)
enc.set(f"{{{SPARKLE_NS}}}edSignature", ed_sig)
enc.set("length", dmg_len)
enc.set("type", "application/octet-stream")

# Prepend the new item (insert after title/link/description, before existing items)
existing_items = channel.findall("item")
for existing in existing_items:
    channel.remove(existing)
channel.append(item)
for existing in existing_items:
    channel.append(existing)

tree.write(appcast_path, encoding="unicode", xml_declaration=True)

# Replace placeholder with real CDATA (ElementTree can't write CDATA natively)
with open(appcast_path) as f:
    content = f.read()
content = content.replace(
    f"CDATA_PLACEHOLDER_{version}",
    f"<![CDATA[{notes_html}]]>"
)
with open(appcast_path, "w") as f:
    f.write(content)

print(f"    appcast.xml updated with v{version} (build {build}).")
PYEOF

cd "$RELEASES_REPO_DIR"
git add appcast.xml
git commit -m "chore: release v${VERSION} (build ${NEW_BUILD})"
git push
cd "$REPO_ROOT"

# Commit only the version bump to the private source repo
git add project.yml
git commit -m "chore: bump to v${VERSION} (build ${NEW_BUILD})"
git push

echo ""
echo "✅  Release v${VERSION} complete!"
echo "   DMG URL:     $DMG_URL"
echo "   Build:       $NEW_BUILD"
echo "   Appcast:     https://raw.githubusercontent.com/shayke-cohen/Odyssey-releases/main/appcast.xml"
