#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the app-icon PNGs in design/logo/png.
# The 16 and 32 px files are hand-tuned small cuts, so they are used as they are;
# the sizes the folder doesn't have are scaled down from the 1024 px master.
set -euo pipefail
cd "${0:A:h:h}"

png=design/logo/png
set=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set"
trap 'rm -rf "${set:h}"' EXIT

cp "$png/glow-app-icon-16.png" "$set/icon_16x16.png"
cp "$png/glow-app-icon-32.png" "$set/icon_16x16@2x.png"
cp "$png/glow-app-icon-32.png" "$set/icon_32x32.png"
for size in 64 128 256; do
  sips -z $size $size "$png/glow-app-icon-1024.png" --out "$set/scaled-$size.png" >/dev/null
done
mv "$set/scaled-64.png" "$set/icon_32x32@2x.png"
mv "$set/scaled-128.png" "$set/icon_128x128.png"
cp "$set/scaled-256.png" "$set/icon_128x128@2x.png"
mv "$set/scaled-256.png" "$set/icon_256x256.png"
cp "$png/glow-app-icon-512.png" "$set/icon_256x256@2x.png"
cp "$png/glow-app-icon-512.png" "$set/icon_512x512.png"
cp "$png/glow-app-icon-1024.png" "$set/icon_512x512@2x.png"

iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
