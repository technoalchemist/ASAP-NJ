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
    | awk '{print $4}')

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

  # Get all original files currently in R2 (not watermarked/thumb/preview versions)
  local r2_files=$(echo "$R2_FILE_CACHE" | grep -vE "_(watermarked|thumb|preview)\.(jpg|jpeg|png|gif|webp)$")

  # Check each R2 original file to see if source still exists
  while IFS= read -r r2_file; do
    [ -z "$r2_file" ] && continue

    # Construct expected source path
    local source_file="${SOURCE_DIR}/${r2_file}"

    if [ ! -f "$source_file" ]; then
      # Source file no longer exists, delete from R2
      log "  Deleting: $r2_file (source file removed)"

      # Get file info for cleanup
      local dir_path=$(dirname "$r2_file")
      local filename=$(basename "$r2_file")
      local name_no_ext="${filename%.*}"
      local ext="${filename##*.}"

      [ "$dir_path" = "." ] && dir_path=""
      [ -n "$dir_path" ] && dir_path="${dir_path}/"

      # Delete original
      delete_from_r2 "$r2_file"

      # Delete associated processed files
      delete_from_r2 "${dir_path}${name_no_ext}_watermarked.${ext}" 2>/dev/null
      delete_from_r2 "${dir_path}${name_no_ext}_thumb.${ext}" 2>/dev/null
      delete_from_r2 "${dir_path}${name_no_ext}_preview.jpg" 2>/dev/null

      : $((deleted_count++))
    fi
  done <<< "$r2_files"

  log "Deleted $deleted_count file(s) from R2"
}