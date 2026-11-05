#!/bin/bash

image_dirs=${1:-}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/inferna/image-selector
index_file="$cache_dir/index.tsv"
pending_video_file=$(mktemp)
pending_image_file=$(mktemp)

mkdir -p "$cache_dir"
trap 'rm -f "$pending_video_file" "$pending_image_file"' EXIT

is_video_path() {
  [[ ${1,,} =~ \.(mp4|m4v|mov|webm|mkv|avi)$ ]]
}

thumbnail_path_for() {
  local image="$1"
  local signature hash

  signature=$(stat -Lc '%s:%Y' "$image") || return
  hash=$(awk -F '\t' -v path="$image" -v sig="$signature" '$1 == path && $2 == sig { print $3; exit }' "$index_file" 2>/dev/null)

  if [[ -z $hash ]]; then
    hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
  fi

  printf '%s/%s.jpg' "$cache_dir" "$hash"
}

generate_video_thumbnail() {
  local image="$1"
  local thumbnail="$2"
  local lock="$thumbnail.lock"
  local lock_fd
  local tmp="$thumbnail.$$.jpg"
  local status

  if [[ -d $lock ]] && (( $(date +%s) - $(stat -c '%Y' "$lock" 2>/dev/null || date +%s) > 120 )); then
    rmdir "$lock" 2>/dev/null
  fi

  exec {lock_fd}>"$lock" || return
  flock -w 30 "$lock_fd" || return
  rm -f "$thumbnail".*.jpg

  [[ -f $thumbnail ]] && return

  if command -v ffmpegthumbnailer >/dev/null 2>&1; then
    timeout -k 5 10 ffmpegthumbnailer -i "$image" -o "$tmp" -s 1536 -q 8 {lock_fd}>&-
    status=$?
  elif command -v ffmpeg >/dev/null 2>&1; then
    timeout -k 5 10 ffmpeg -y -ss 00:00:01 -i "$image" -vframes 1 -vf "scale=1536:864:force_original_aspect_ratio=increase,crop=1536:864" -q:v 2 "$tmp" {lock_fd}>&-
    status=$?
  else
    status=1
  fi

  if (( status == 0 )) && [[ -f $tmp ]]; then
    mv -f "$tmp" "$thumbnail"
  else
    rm -f "$tmp" "$thumbnail"
    (( status == 124 || status == 137 )) || : >"$thumbnail.failed"
    return 1
  fi
}

generate_image_thumbnail() {
  local image="$1"
  local thumbnail="$2"
  local lock="$thumbnail.lock"
  local lock_fd
  local tmp="$thumbnail.$$.jpg"
  local thumbnail_command

  if [[ -d $lock ]] && (( $(date +%s) - $(stat -c '%Y' "$lock" 2>/dev/null || date +%s) > 120 )); then
    rmdir "$lock" 2>/dev/null
  fi

  exec {lock_fd}>"$lock" || return
  flock -w 30 "$lock_fd" || return
  rm -f "$thumbnail".*.jpg

  [[ -f $thumbnail ]] && return

  if command -v vipsthumbnail >/dev/null 2>&1; then
    thumbnail_command=(env VIPS_CONCURRENCY=1 vipsthumbnail "$image" --size 1536x864 --smartcrop=centre --path "$tmp[Q=82,strip]")
  elif command -v magick >/dev/null 2>&1; then
    thumbnail_command=(magick "$image" -resize 1536x864^ -gravity center -extent 1536x864 -quality 82 "$tmp")
  elif command -v convert >/dev/null 2>&1; then
    thumbnail_command=(convert "$image" -resize 1536x864^ -gravity center -extent 1536x864 -quality 82 "$tmp")
  else
    return 1
  fi

  if "${thumbnail_command[@]}" {lock_fd}>&-; then
    mv -f "$tmp" "$thumbnail"
  else
    rm -f "$tmp" "$thumbnail"
    return 1
  fi
}

drain_pending_video_thumbnails() {
  local video_jobs

  [[ -s $pending_video_file ]] || return 0

  video_jobs=$(( $(nproc) / 4 ))
  (( video_jobs > 0 )) || video_jobs=1
  export -f generate_video_thumbnail
  xargs -a "$pending_video_file" -0 -n 2 -P "$video_jobs" \
    bash -c 'generate_video_thumbnail "$1" "$2"' _ >/dev/null 2>&1 || true
}

drain_pending_image_thumbnails() {
  local image_jobs

  [[ -s $pending_image_file ]] || return 0

  image_jobs=$(( $(nproc) / 2 ))
  (( image_jobs > 0 )) || image_jobs=1
  (( image_jobs > 4 )) && image_jobs=4
  export -f generate_image_thumbnail
  xargs -a "$pending_image_file" -0 -n 2 -P "$image_jobs" \
    bash -c 'generate_image_thumbnail "$1" "$2"' _ >/dev/null 2>&1 || true
}

thumbnail_for() {
  local image="$1"
  local thumbnail legacy_hash

  thumbnail=$(thumbnail_path_for "$image") || return

  if [[ ! -f $thumbnail ]] && ! is_video_path "$image"; then
    # Older on-demand picker code keyed fallback thumbnails by file content.
    # Keep finding those if a user still has them cached.
    legacy_hash=$(md5sum "$image" 2>/dev/null | cut -d ' ' -f 1)
    [[ -n $legacy_hash && -f $cache_dir/$legacy_hash.jpg ]] && thumbnail="$cache_dir/$legacy_hash.jpg"
  fi

  if [[ -f $thumbnail ]]; then
    printf '%s' "$thumbnail"
  elif ! is_video_path "$image"; then
    printf '%s' "$image"
  fi
}

mapfile -d '' -t images < <(
  while IFS= read -r dir; do
    [[ -n $dir && -d $dir ]] || continue
    find -L "$dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \
         -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \) \
      -print0 2>/dev/null
  done <<<"$image_dirs" | sort -z
)

for image in "${images[@]}"; do
  if is_video_path "$image"; then
    thumbnail=$(thumbnail_path_for "$image") || continue
    [[ -f $thumbnail || -f $thumbnail.failed ]] || printf '%s\0%s\0' "$image" "$thumbnail" >>"$pending_video_file"
  else
    thumbnail=$(thumbnail_path_for "$image") || continue
    [[ -f $thumbnail ]] || printf '%s\0%s\0' "$image" "$thumbnail" >>"$pending_image_file"
  fi
done

drain_pending_video_thumbnails
drain_pending_image_thumbnails

for image in "${images[@]}"; do
  thumbnail=$(thumbnail_for "$image")
  [[ -n $thumbnail ]] || continue
  printf '%s\t%s\n' "$image" "$thumbnail"
done
