#!/bin/bash
# Pulls new videos listed in uto-media/main/manifest.json.
# Each entry: {"id","parts":[raw URLs],"sha256","bytes","stream":bool,"public":bool}
#   public -> copy is served at https://<host>/<id>.mp4 (for vidIQ imports)
#   stream -> a normalised copy is added to the 24/7 live loop
set -euo pipefail
BASE=/srv/uto
RAW=https://raw.githubusercontent.com/Bhat015/uto-media/main/vps
# keep the server scripts current (installed copies in /usr/local/bin exec these)
mkdir -p "$BASE/bin"
for f in uto-sync.sh uto-stream.sh uto-broadcast.py; do
  if curl -fsSL "$RAW/$f?$(date +%s)" -o "$BASE/bin/$f.new" && { [[ $f == *.py ]] && python3 -m py_compile "$BASE/bin/$f.new" || bash -n "$BASE/bin/$f.new"; }; then
    chmod 755 "$BASE/bin/$f.new"; mv "$BASE/bin/$f.new" "$BASE/bin/$f"
  else rm -f "$BASE/bin/$f.new"; fi
done
MAN=$(curl -fsSL "https://raw.githubusercontent.com/Bhat015/uto-media/main/manifest.json?$(date +%s)") || exit 0
# live stream switch: manifest "liveStream": false stops the 24/7 loop (uto-stream.sh then idles)
if [ "$(jq -r 'if has("liveStream") then .liveStream else true end' <<<"$MAN")" = false ]; then
  [ -e "$BASE/stream.off" ] || echo "live stream switched off"
  touch "$BASE/stream.off"; pkill -u "$(id -u)" -f 'rtmps://a.rtmps.youtube.com' 2>/dev/null || true
else rm -f "$BASE/stream.off"; fi
echo "$MAN" | jq -c '.videos[]' | while read -r v; do
  id=$(jq -r .id <<<"$v"); sha=$(jq -r .sha256 <<<"$v")
  [[ "$id" =~ ^[a-z0-9-]+$ ]] || { echo "skip bad id $id"; continue; }
  src="$BASE/parts/$id.mp4"
  if [ ! -s "$src" ] || [ "$(sha256sum "$src" | cut -d' ' -f1)" != "$sha" ]; then
    tmp="$src.tmp"; : > "$tmp"
    ok=1
    for u in $(jq -r '.parts[]' <<<"$v"); do curl -fsSL "$u" >> "$tmp" || { ok=0; break; }; done
    if [ $ok = 1 ] && [ "$(sha256sum "$tmp" | cut -d' ' -f1)" = "$sha" ]; then mv "$tmp" "$src"; echo "got $id";
    else rm -f "$tmp"; echo "pending $id (parts not available or checksum mismatch)"; continue; fi
  fi
  if [ "$(jq -r '.public // false' <<<"$v")" = true ] && [ ! -e "$BASE/public/$id.mp4" ]; then
    ln -f "$src" "$BASE/public/$id.mp4" 2>/dev/null || cp "$src" "$BASE/public/$id.mp4"
  fi
  if [ ! -e "$BASE/stream.off" ] && [ "$(jq -r '.stream // false' <<<"$v")" = true ] && [ ! -s "$BASE/stream/$id.ts" ] && [ "$(jq -r '.streamParts // empty | length' <<<"$v")" != "" ]; then
    # stream copy already prepared off-server: just download and verify it (saves the server's CPU)
    tmp="$BASE/stream/$id.ts.tmp"; : > "$tmp"; ok=1
    for u in $(jq -r '.streamParts[]' <<<"$v"); do curl -fsSL "$u" >> "$tmp" || { ok=0; break; }; done
    if [ $ok = 1 ] && [ "$(sha256sum "$tmp" | cut -d' ' -f1)" = "$(jq -r .streamSha256 <<<"$v")" ]; then mv "$tmp" "$BASE/stream/$id.ts"; echo "stream-ready $id (prepared)";
    else rm -f "$tmp"; echo "pending stream copy $id"; fi
  fi
  if [ ! -e "$BASE/stream.off" ] && [ "$(jq -r '.stream // false' <<<"$v")" = true ] && [ ! -s "$BASE/stream/$id.ts" ] && [ -z "$(jq -r '.streamParts // empty' <<<"$v")" ]; then
    # one uniform profile so the live loop can copy streams without re-encoding
    ffmpeg -nostdin -v error -y -i "$src" -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p" \
      -c:v libx264 -preset veryfast -b:v 4500k -maxrate 4500k -bufsize 9000k -g 60 -keyint_min 60 -sc_threshold 0 \
      -c:a aac -b:a 128k -ar 44100 -ac 2 -f mpegts "$BASE/stream/$id.ts.tmp" && mv "$BASE/stream/$id.ts.tmp" "$BASE/stream/$id.ts" && echo "stream-ready $id"
  fi
done
# remove library items no longer in the manifest
keep=$(echo "$MAN" | jq -r '.videos[].id')
for f in "$BASE"/parts/*.mp4 "$BASE"/public/*.mp4 "$BASE"/stream/*.ts; do
  [ -e "$f" ] || continue; b=$(basename "$f"); b=${b%.*}
  grep -qx "$b" <<<"$keep" || { rm -f "$f"; echo "removed $b"; }
done
# status page: https://<host>/status.txt
{ echo "updated: $(date '+%F %T %Z')"; echo "stream library:"; for f in "$BASE"/stream/*.ts; do [ -e "$f" ] && echo "  $(basename "$f") $(du -m "$f" | cut -f1) MB"; done
  echo "stream service: $(systemctl is-active uto-stream 2>/dev/null)"; if [ -e "$BASE/stream.off" ]; then echo "live stream: switched off in manifest"; fi; } > "$BASE/public/status.txt.tmp" && mv "$BASE/public/status.txt.tmp" "$BASE/public/status.txt"
