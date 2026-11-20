#!/usr/bin/env bash
# Builds the Linux x64 app, broker and nsh binaries, then packages the shared
# Resources layout as an installable deb and an extractable tar.gz.
#
#   RELEASE_OUT=<dir>          where artifacts go (default dist/)
#   CARGO_TARGET_DIR           app and nsh target dir (default app/target)
#   BROKER_TARGET_DIR          broker target dir (default broker/target)
#   NSH_TARGET_DIR             nsh target dir (default CARGO_TARGET_DIR)
#   BUWIZ_BOT_BIN, BUWIZ_BROKER_BIN, NSH_BIN, NSH_HOST_BIN
#                              prebuilt binaries to package instead of building
#   OFFICE_DIST, OFFICE_FONTS, MATERIAL_SYMBOLS_TTF
#   NODE_MODULES=<dir>         office's node_modules (default office/node_modules)
set -euo pipefail

source "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/../lib/no-old-names.sh"

[ "$(uname -s)" = Linux ] || die "build-linux.sh must run on Linux"
[ "$(uname -m)" = x86_64 ] || die "Linux release builds are x86_64 only"

VERSION="$(awk -F'"' '/^\[/{s=$0} s=="[package]" && /^version *=/{print $2; exit}' "$ROOT/app/Cargo.toml")"
BIN_NAME="$(awk -F'"' '/^\[/{s=$0} s=="[[bin]]" && /^name *=/{print $2; exit}' "$ROOT/app/Cargo.toml")"
[ -n "$BIN_NAME" ] || BIN_NAME="$(awk -F'"' '/^\[/{s=$0} s=="[package]" && /^name *=/{print $2; exit}' "$ROOT/app/Cargo.toml")"
[ -n "$VERSION" ] && [ -n "$BIN_NAME" ] || die "no version or binary name in app/Cargo.toml"

APP_TARGET="${CARGO_TARGET_DIR:-$ROOT/app/target}"
BROKER_TARGET="${BROKER_TARGET_DIR:-$ROOT/broker/target}"
NSH_TARGET="${NSH_TARGET_DIR:-${CARGO_TARGET_DIR:-$ROOT/nsh/target}}"
cargo_release() { # <workspace dir> <target dir> <cargo args...>
  local dir="$1" target="$2"
  shift 2
  (cd "$dir" && RUSTC_WRAPPER='' CARGO_TARGET_DIR="$target" "$ROOT/scripts/wait-build" cargo build --release --locked "$@")
}

OFFICE="$ROOT/office"
ASSETS="$ROOT/broker/buwiz-broker/assets"
NODE_MODULES="${NODE_MODULES:-$OFFICE/node_modules}"
OFFICE_FONTS="${OFFICE_FONTS:-$NODE_MODULES/@betteroffice/fonts}"
OFFICE_DIST="${OFFICE_DIST:-$OFFICE/editor/dist}"
[ -d "$NODE_MODULES/@betteroffice" ] || die "no @betteroffice packages in $NODE_MODULES: run npm ci in office/ (or set NODE_MODULES)"
[ -f "$OFFICE_FONTS/assets/Carlito-Regular.ttf" ] || die "no @betteroffice/fonts at $OFFICE_FONTS: run npm ci in office/ (or set OFFICE_FONTS)"
[ -f "$OFFICE_DIST/editor.js" ] || die "no office editor bundle in $OFFICE_DIST: run npm run build:office-editor in office/ (or set OFFICE_DIST)"

SYMBOLS_URL="https://fonts.gstatic.com/s/materialsymbolsoutlined/v382/kJF1BvYX7BgnkSrUwT8OhrdQw4oELdPIeeII9v6oDMzByHX9rA6RzaxHMPdY43zj-jCxv3fzvRNU22ZXGJpEpjC_1v-p_4MrImHCIJIZrDCvHOem.ttf"
SYMBOLS_SHA256=69b4db8f8971c5206adb2d3891787c33eee828271fa56209e05ee0e3202729dd
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
SYMBOLS="${MATERIAL_SYMBOLS_TTF:-$CACHE_HOME/buwiz-bot/fonts/MaterialSymbolsOutlined-v382.ttf}"
if [ ! -f "$SYMBOLS" ] && [ -z "${MATERIAL_SYMBOLS_TTF:-}" ]; then
  mkdir -p "$(dirname "$SYMBOLS")"
  curl -fsSL -o "$SYMBOLS.part" "$SYMBOLS_URL" && mv "$SYMBOLS.part" "$SYMBOLS" || rm -f "$SYMBOLS.part"
fi
[ -f "$SYMBOLS" ] && [ "$(sha256sum "$SYMBOLS" | cut -d' ' -f1)" = "$SYMBOLS_SHA256" ] \
  || die "no Material Symbols Outlined font (sha256 $SYMBOLS_SHA256) at $SYMBOLS: download $SYMBOLS_URL there, or set MATERIAL_SYMBOLS_TTF"

if [ -z "${BUWIZ_BOT_BIN:-}" ]; then
  cargo_release "$ROOT/app" "$APP_TARGET" --bin "$BIN_NAME" --no-default-features
  BUWIZ_BOT_BIN="$APP_TARGET/release/$BIN_NAME"
fi
if LC_ALL=C grep -q 'gpui-agent: serving' "$BUWIZ_BOT_BIN"; then
  die "$BUWIZ_BOT_BIN has the gpui-agent server in it: build with --no-default-features"
fi
for setting in BUWIZ_HUB_POSTED_ALLOW GPUI_AGENT_ACTOR BUWIZ_HUB_FULL_TEXT; do
  if LC_ALL=C grep -q "$setting" "$BUWIZ_BOT_BIN"; then
    die "$BUWIZ_BOT_BIN has the test setting $setting in it: build with --no-default-features"
  fi
done

if [ -z "${BUWIZ_BROKER_BIN:-}" ]; then
  cargo_release "$ROOT/broker" "$BROKER_TARGET" -p buwiz-broker
fi
BUWIZ_BROKER_BIN="${BUWIZ_BROKER_BIN:-$BROKER_TARGET/release/buwiz-broker}"

if [ -z "${NSH_BIN:-}${NSH_HOST_BIN:-}" ]; then
  cargo_release "$ROOT/nsh" "$NSH_TARGET" -p nsh-cli -p nsh-linux-host --no-default-features
  NSH_BIN="$NSH_TARGET/release/nsh"
  NSH_HOST_BIN="$NSH_TARGET/release/nsh-linux-host"
fi
for binary in "$BUWIZ_BOT_BIN" "$BUWIZ_BROKER_BIN" "${NSH_BIN:-}" "${NSH_HOST_BIN:-}"; do
  [ -x "$binary" ] || die "missing binary: ${binary:-nsh or nsh-linux-host (set both NSH_BIN and NSH_HOST_BIN, or neither)}"
done

BOT_VERSION="$("$BUWIZ_BOT_BIN" --version)"
[ "$BOT_VERSION" = "buwiz-bot $VERSION" ] || die "app reports '$BOT_VERSION', expected 'buwiz-bot $VERSION'"
BROKER_VERSION="$("$BUWIZ_BROKER_BIN" --version)"
[ "$BROKER_VERSION" = "buwiz-broker $VERSION" ] || die "broker reports '$BROKER_VERSION', expected 'buwiz-broker $VERSION'"
echo "verified $BOT_VERSION and $BROKER_VERSION"

NAME="Buwiz-Bot-$VERSION-linux-x64"
TAR_NAME="buwiz-bot-$VERSION-linux-x64"
DEB="$OUT/$NAME.deb"
TARBALL="$OUT/$NAME.tar.gz"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RESOURCES="$WORK/Resources"
mkdir -p "$RESOURCES/fonts/office/LICENSES" "$RESOURCES/broker/bin" \
  "$RESOURCES/broker/server/office/editor/dist" "$RESOURCES/broker/node_modules"

cp "$SYMBOLS" "$RESOURCES/fonts/MaterialSymbolsOutlined.ttf"
cp "$ROOT/app/fonts/MaterialSymbolsOutlined-LICENSE" "$RESOURCES/fonts/MaterialSymbolsOutlined-LICENSE"
cp "$OFFICE_FONTS"/assets/*.ttf "$RESOURCES/fonts/office/"
cp "$OFFICE_FONTS"/LICENSES/* "$RESOURCES/fonts/office/LICENSES/"
cp "$OFFICE_FONTS/LICENSE" "$RESOURCES/fonts/office/LICENSE"

BROKER_RESOURCES="$RESOURCES/broker"
cp "$BUWIZ_BROKER_BIN" "$BROKER_RESOURCES/buwiz-broker"
cp "$NSH_BIN" "$BROKER_RESOURCES/bin/nsh"
cp "$NSH_HOST_BIN" "$BROKER_RESOURCES/bin/nsh-linux-host"
cp "$OFFICE/viewer.html" "$BROKER_RESOURCES/server/office/viewer.html"
cp "$OFFICE/editor/editor.html" "$BROKER_RESOURCES/server/office/editor/editor.html"
cp -R "$OFFICE/seeds" "$BROKER_RESOURCES/server/office/seeds"
cp -R "$OFFICE_DIST/." "$BROKER_RESOURCES/server/office/editor/dist/"
cp -R "$ASSETS/plugins" "$BROKER_RESOURCES/server/plugins"
cp "$ASSETS/trust.json" "$BROKER_RESOURCES/server/trust.json"
cp -R "$NODE_MODULES/@betteroffice" "$BROKER_RESOURCES/node_modules/@betteroffice"
cp "$BUWIZ_BOT_BIN" "$WORK/buwiz-bot"
if [ -f "$ROOT/app/resources/AppIcon.png" ]; then
  cp "$ROOT/app/resources/AppIcon.png" "$RESOURCES/AppIcon.png"
fi

DEPS=("libgtk-4-1 (>= 4.14)" "libsqlite3-0")
for binary in "$BUWIZ_BOT_BIN" "$BUWIZ_BROKER_BIN" "$NSH_BIN" "$NSH_HOST_BIN"; do
  output="$(ldd "$binary")" || die "ldd failed for $binary"
  if printf '%s\n' "$output" | grep -q 'not found'; then
    die "unresolved runtime library for $binary: $(printf '%s\n' "$output" | grep 'not found' | tr '\n' ' ')"
  fi
  while IFS= read -r library; do
    [ -n "$library" ] || continue
    library_path="$(readlink -f "$library")" || die "could not resolve runtime library $library ($binary)"
    package=""
    for candidate in "$library_path" "$library"; do
      package="$(dpkg-query -S "$candidate" 2>/dev/null | sed -n '1s/: .*//p' | sed 's/:.*$//' || true)"
      [ -n "$package" ] && break
    done
    [ -n "$package" ] || die "could not find the Debian package for runtime library $library ($binary)"
    case "$package" in
      libgtk-4-1|libsqlite3-0) continue ;;
    esac
    found=false
    for dependency in "${DEPS[@]}"; do
      [ "$dependency" = "$package" ] && found=true
    done
    [ "$found" = true ] || DEPS+=("$package")
  done < <(printf '%s\n' "$output" | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}')
done
DEPENDS="$(printf '%s, ' "${DEPS[@]}")"
DEPENDS="${DEPENDS%, }"

desktop_text() {
  local executable="$1" icon_line="$2"
  printf '[Desktop Entry]\nType=Application\nName=Buwiz Bot\nExec=%s %%u\nTerminal=false\nMimeType=x-scheme-handler/buwiz;\nCategories=Office;Utility;\nStartupWMClass=com.buwiz.bot\n%s\n' "$executable" "$icon_line"
}

PKG="$WORK/deb"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/buwiz-bot/bin" "$PKG/usr/bin" "$PKG/usr/share/applications"
cp "$BUWIZ_BOT_BIN" "$PKG/opt/buwiz-bot/bin/buwiz-bot"
ln -s /opt/buwiz-bot/bin/buwiz-bot "$PKG/usr/bin/buwiz-bot"
ICON_LINE=""
if [ -f "$ROOT/app/resources/AppIcon.png" ]; then
  mkdir -p "$PKG/usr/share/icons/hicolor/1024x1024/apps"
  cp "$ROOT/app/resources/AppIcon.png" "$PKG/usr/share/icons/hicolor/1024x1024/apps/com.buwiz.bot.png"
  ICON_LINE="Icon=com.buwiz.bot"
fi
desktop_text "/opt/buwiz-bot/bin/buwiz-bot" "$ICON_LINE" > "$PKG/usr/share/applications/com.buwiz.bot.desktop"
cp -R "$RESOURCES" "$PKG/opt/buwiz-bot/Resources"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: buwiz-bot
Version: $VERSION
Section: office
Priority: optional
Architecture: amd64
Depends: $DEPENDS
Maintainer: Goldcoders Corp
Description: Buwiz Bot desktop application
CONTROL
dpkg-deb --build --root-owner-group "$PKG" "$DEB" >/dev/null

TOP="$WORK/$TAR_NAME"
mkdir -p "$TOP/bin" "$TOP/share/applications"
cp "$WORK/buwiz-bot" "$TOP/bin/buwiz-bot"
cp -R "$RESOURCES" "$TOP/Resources"
desktop_text "/opt/buwiz-bot/bin/buwiz-bot" "$ICON_LINE" > "$TOP/share/applications/com.buwiz.bot.desktop"
if [ -f "$ROOT/app/resources/AppIcon.png" ]; then
  mkdir -p "$TOP/share/icons/hicolor/1024x1024/apps"
  cp "$ROOT/app/resources/AppIcon.png" "$TOP/share/icons/hicolor/1024x1024/apps/com.buwiz.bot.png"
fi
cat > "$TOP/README.md" <<'README'
# Buwiz Bot for Linux

Requires GTK 4.14 or later, SQLite 3 and WebKitGTK 6.0. The broker, office
editor assets, and fonts are bundled under `Resources/`. Run `bin/buwiz-bot`
from this directory. For desktop integration, install this directory as
`/opt/buwiz-bot` and register `share/applications/com.buwiz.bot.desktop`.
README
tar -C "$WORK" -czf "$TARBALL" "$TAR_NAME"

for artifact in "$DEB" "$TARBALL"; do
  (cd "$OUT" && sha256sum "$(basename "$artifact")" > "$(basename "$artifact").sha256")
  echo "artifact: $artifact"
  echo "sha256: $(sha256sum "$artifact" | cut -d' ' -f1)"
  echo "size: $(stat -c %s "$artifact")"
done
