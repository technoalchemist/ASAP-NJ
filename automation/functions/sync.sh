#!/bin/bash
#
# File synchronization and change detection functions
#

# Global variable to cache R2 file list
R2_FILE_CACHE=""

cache_r2_files() {
  log "Caching R2 file list for fast change detection..."
  R2_FILE_CACHE=$(aws s3 ls "s3://${R2_BUCKET}/" \
    --endpoint-url "$R2_ENDPOINT" \
    --recursive \
    | awk '{$1=$2=$3=""; print substr($0,4)}')

  local file_count=$(echo "$R2_FILE_CACHE" | grep -v '^$' | wc -l)
  log "Cached $file_count files from R2"
}

needs_processing() {
  local local_file="$1"
  local r2_path="$2"

  # Extract filename parts
  local filename=$(basename "$r2_path")
  local name_no_ext="${filename%.*}"
  local ext="${filename##*.}"

  # Get directory path
  local dir_path=$(dirname "$r2_path")
  [ "$dir_path" = "." ] && dir_path=""
  [ -n "$dir_path" ] && dir_path="${dir_path}/"

  # Determine what to check based on file type
  local check_file=""
  if echo "$filename" | grep -qiE "\.(${VIDEO_EXTS})$"; then
    # For videos, check if the video file itself exists
    check_file="${r2_path}"
  else
    # For images, check if watermarked version exists
    check_file="${dir_path}${name_no_ext}_watermarked.${ext}"
  fi

  # Check against cached R2 file list
  if echo "$R2_FILE_CACHE" | grep -qF "$check_file"; then
    # File exists in R2, skip
    return 1
  fi

  # File doesn't exist in R2, needs processing
  return 0
}

sync_deletions() {
  log "Checking for files to delete from R2..."

  local deleted_count=0

  # Get all files from R2 cache
  # Filter to only original files (not _watermarked, _thumb, _preview)
  local r2_originals=$(echo "$R2_FILE_CACHE" | grep -v -E "_(watermarked|thumb|preview)\.")

  # Check each original file to see if source still exists
  while IFS= read -r r2_file; do
    [ -z "$r2_file" ] && continue

    # Skip if this looks like a malformed entry (no extension or path)
    if ! echo "$r2_file" | grep -qE '\.[a-zA-Z0-9]+$'; then
      log "  Skipping malformed R2 entry: '$r2_file'"
      continue
    fi

    # Construct expected source path
    local source_file="${SOURCE_DIR}/${r2_file}"

    if [ ! -f "$source_file" ]; then
      # Source file no longer exists, delete from R2
      log "  Source removed, deleting from R2: $r2_file"

      # Get file info for cleanup
      local dir_path=$(dirname "$r2_file")
      local filename=$(basename "$r2_file")
      local name_no_ext="${filename%.*}"
      local ext="${filename##*.}"

      [ "$dir_path" = "." ] && dir_path=""
      [ -n "$dir_path" ] && dir_path="${dir_path}/"

      # Delete original
      delete_from_r2 "$r2_file"

      # Delete associated processed files (ignore errors if they don't exist)
      delete_from_r2 "${dir_path}${name_no_ext}_watermarked.${ext}" 2>/dev/null || true
      delete_from_r2 "${dir_path}${name_no_ext}_thumb.${ext}" 2>/dev/null || true
      delete_from_r2 "${dir_path}${name_no_ext}_thumb.jpg" 2>/dev/null || true
      delete_from_r2 "${dir_path}${name_no_ext}_preview.jpg" 2>/dev/null || true

      : $((deleted_count++))
    fi
  done <<< "$r2_originals"

  log "Deleted $deleted_count file(s) from R2"
}