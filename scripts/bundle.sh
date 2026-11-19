#!/bin/zsh
# Builds Glow.app into build/: a universal release build for Apple silicon and
# Intel Macs.
#
#   scripts/bundle.sh                     signed with "Glow Local Signing" when
#                                         scripts/signing-identity.sh has made it,
#                                         otherwise ad hoc
#   GLOW_SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#   GLOW_ARCHS=arm64 scripts/bundle.sh    one architecture, quicker
#   GLOW_CONFIGURATION=debug scripts/bundle.sh
#                                         a debug build, with the debug-only
#                                         flags, such as -GlowSimulatedMonitors;
#                                         never for a release
#   scripts/bundle.sh <app> [<dSYM>]      to another .app path, and the debug
#                                         symbols to a .dSYM path; paths are
#                                         taken from where it's run
#
# scripts/release.sh builds through this script, with its own paths and
# GLOW_ARCHS=arm64, so a release is assembled exactly as a local build is.
#
# The bundle ID, copyright and links come from Resources/release.env. They are
# stamped on the bundle's copy of Info.plist, never on Resources/Info.plist.
#
# macOS ties the Accessibility grant (the brightness keys) to the app's
# signature. An ad-hoc signature changes with every build, so each rebuild
# needs the permission granted again; a stable identity keeps it.
#
# Release builds leave out the debug-only flags (--probe-displays,
# --ddc-selftest, --snapshot-ui, -GlowSimulatedMonitors). They build in
# .build-bundle/, never the default .build/.
set -euo pipefail

if (( $# > 2 )); then
  echo "usage: scripts/bundle.sh [output .app path] [dSYM path]" >&2
  exit 64
fi
# Paths given are read from the directory the script is run in, before it moves
# to the repository.
app="build/Glow.app"
dsym=""
if [[ -n ${1:-} ]]; then app="${1:a}"; fi
if [[ -n ${2:-} ]]; then dsym="${2:a}"; fi
# The bundle and the dSYM are deleted and made again, so a path that isn't one
# is refused.
if [[ $app != *?.app ]]; then
  echo "error: the output must be a .app path, not '$app'" >&2
  exit 64
fi
if [[ -n $dsym && $dsym != *?.dSYM ]]; then
  echo "error: the debug symbols must go to a .dSYM path, not '$dsym'" >&2
  exit 64
fi

root="${0:A:h:h}"
cd "$root"

configuration=${GLOW_CONFIGURATION:-release}
if [[ $configuration != (release|debug) ]]; then
  echo "error: GLOW_CONFIGURATION must be release or debug, not '$configuration'" >&2
  exit 64
fi
archs=(${=GLOW_ARCHS:-arm64 x86_64})
slices=()
for arch in $archs; do
  swift build -c "$configuration" --triple "$arch-apple-macosx14.0" --scratch-path ".build-bundle/$arch"
  slices+=(".build-bundle/$arch/$configuration/Glow")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
# plutil takes each value as one argument, so quotes and apostrophes in a name
# stay as they are. A link left empty keeps the source plist's placeholder.
source Resources/release.env
plist="$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "${BUNDLE_ID:?is empty in Resources/release.env}" "$plist"
plutil -replace NSHumanReadableCopyright -string "${COPYRIGHT:?is empty in Resources/release.env}" "$plist"
for key variable in GlowWebsiteURL WEBSITE_URL \
                    GlowSupportURL SUPPORT_URL GlowSupportEmail SUPPORT_EMAIL \
                    GlowPrivacyPolicyURL PRIVACY_POLICY_URL GlowEULAURL EULA_URL; do
  if [[ -n ${(P)variable:-} ]]; then
    plutil -replace "$key" -string "${(P)variable}" "$plist"
  fi
done
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# MonitorControl's MIT licence goes with every copy of the parts of its DDC approach Glow adapts.
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
lipo -create "${slices[@]}" -output "$app/Contents/MacOS/Glow"
# When asked, the debug symbols are kept apart before strip drops them, so a
# crash report from this build can still be read. dsymutil gathers them from
# the build's object files into a dSYM with the binary's UUID.
if [[ -n $dsym ]]; then
  rm -rf "$dsym"
  mkdir -p "${dsym:h}"
  dsymutil "$app/Contents/MacOS/Glow" -o "$dsym"
fi
# Local symbols are only for debugging; dropping them shrinks the app.
strip -x "$app/Contents/MacOS/Glow"

local_name="Glow Local Signing"
local_keychain="$HOME/Library/Keychains/glow-signing.keychain-db"
if [[ -n ${GLOW_SIGN_IDENTITY:-} ]]; then
  # A Developer ID signature needs a secure timestamp to be notarized.
  codesign --force --options runtime --timestamp --sign "$GLOW_SIGN_IDENTITY" "$app"
elif [[ -f $local_keychain ]] && security find-certificate -c "$local_name" "$local_keychain" >/dev/null 2>&1; then
  security unlock-keychain -p glow-local-signing "$local_keychain"
  codesign --force --options runtime --keychain "$local_keychain" --sign "$local_name" "$app"
else
  codesign --force --options runtime --sign - "$app"
  echo "Signed ad hoc. Run scripts/signing-identity.sh once to keep the Accessibility grant across builds."
fi

echo "Built $app ($(du -sh "$app" | cut -f1), $(lipo -archs "$app/Contents/MacOS/Glow"), $configuration)"
