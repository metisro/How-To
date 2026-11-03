#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  sudo ./install-artplayer-patch.sh \
    --web-root /path/to/frontend \
    --assets-dir /path/to/patched-assets \
    --runtime app.HASH.js \
    --video-chunk VIDEO.HASH.js \
    --player-chunk PLAYER.HASH.js

The assets directory must contain index.html and the three named JavaScript
files. This script validates and installs a prepared patch set; it does not
rewrite minified webpack code for an arbitrary ReCasaOS build.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

web_root=
assets_dir=
runtime=
video_chunk=
player_chunk=

while (($#)); do
    case "$1" in
        --web-root)     (($# >= 2)) || die "--web-root needs a value"; web_root=$2; shift 2 ;;
        --assets-dir)   (($# >= 2)) || die "--assets-dir needs a value"; assets_dir=$2; shift 2 ;;
        --runtime)      (($# >= 2)) || die "--runtime needs a value"; runtime=$2; shift 2 ;;
        --video-chunk)  (($# >= 2)) || die "--video-chunk needs a value"; video_chunk=$2; shift 2 ;;
        --player-chunk) (($# >= 2)) || die "--player-chunk needs a value"; player_chunk=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n $web_root && -n $assets_dir && -n $runtime && -n $video_chunk && -n $player_chunk ]] || { usage >&2; exit 2; }
[[ $runtime != */* && $video_chunk != */* && $player_chunk != */* ]] || die "asset names must be filenames, not paths"
[[ $runtime != "$video_chunk" && $runtime != "$player_chunk" && $video_chunk != "$player_chunk" ]] || die "JavaScript filenames must be distinct"

[[ $EUID -eq 0 ]] || die "run with sudo so file ownership and permissions can be preserved"
[[ -d $web_root && -d $assets_dir ]] || die "web root or assets directory does not exist"
web_root=$(realpath -e -- "$web_root")
assets_dir=$(realpath -e -- "$assets_dir")
[[ $web_root != "$assets_dir" ]] || die "assets directory must be separate from the live web root"

for file in index.html "$runtime" "$video_chunk" "$player_chunk"; do
    [[ -f $assets_dir/$file ]] || die "missing staged asset: $assets_dir/$file"
done
for file in "$runtime" "$video_chunk" "$player_chunk"; do
    [[ -s $assets_dir/$file ]] || die "staged asset is empty: $file"
    node --check "$assets_dir/$file" >/dev/null || die "JavaScript syntax check failed: $file"
done

grep -Fq "$runtime" "$assets_dir/index.html" || die "index.html does not reference runtime $runtime"
grep -Fq "$video_chunk" "$assets_dir/$runtime" || die "runtime does not reference video chunk $video_chunk"
grep -Fq "$player_chunk" "$assets_dir/$runtime" || die "runtime does not reference player chunk $player_chunk"

stamp=$(date +%Y%m%d-%H%M%S)
backup="/var/backups/recasaos-artplayer-$stamp"
mkdir -p -m 0755 -- "$backup"
for file in index.html "$runtime" "$video_chunk" "$player_chunk"; do
    if [[ -e $web_root/$file ]]; then
        cp -a -- "$web_root/$file" "$backup/"
    fi
done

printf 'Backup created at: %s\n' "$backup"
tmp_dir=$(mktemp -d "$web_root/.artplayer-install.XXXXXX")
cleanup() { rm -rf -- "$tmp_dir"; }
trap cleanup EXIT

for file in index.html "$runtime" "$video_chunk" "$player_chunk"; do
    install -m 0644 -- "$assets_dir/$file" "$tmp_dir/$file"
done

# Install chunks and runtime before index.html so the document never points at
# new files that have not yet been copied into place.
for file in "$runtime" "$video_chunk" "$player_chunk" index.html; do
    if [[ -e $web_root/$file ]]; then
        chmod --reference="$web_root/$file" "$tmp_dir/$file"
        chown --reference="$web_root/$file" "$tmp_dir/$file"
    fi
    mv -f -- "$tmp_dir/$file" "$web_root/$file"
done

printf 'Installed ArtPlayer patch assets. Hard-refresh the ReCasaOS page and verify the player and subtitles.\n'
printf 'To roll back, restore the files present in %s to %s.\n' "$backup" "$web_root"
