#!/bin/bash
#
# File synchronization and change detection functions
#

get_file_hash() {
  local file="$1"
  md5sum "$file" | awk '{print $1}'
}

get_file_timestamp() {
  local file="$1"
  stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
}

needs_processing() {
  local local_file="$1"
  local r2_path="$2"

  # Check if file exists in R2
  aws s3 ls "s3://${R2_BUCKET}/${r2_path}" \
    --endpoint-url "$R2_ENDPOINT" &>/dev/null

  if [ $? -ne 0 ]; then
    # File doesn't exist in R2, needs processing
    return 0
  fi

  # File exists in R2 - check if local file is newer
  # For now, we'll reprocess if file exists locally
  # More sophisticated: compare timestamps or hashes
  # But for Gary's use case, if it's in R2, skip it
  return 1
}

list_r2_files_in_path() {
  local path_prefix="$1"

  aws s3 ls "s3://${R2_BUCKET}/${path_prefix}" \
    --endpoint-url "$R2_ENDPOINT" \
    --recursive \
    | awk '{print $4}'
}

sync_deletions() {
  log "Checking for files to delete from R2..."

  local deleted_count=0

  # Get all files currently in R2
  local r2_files=$(aws s3 ls "s3://${R2_BUCKET}/" \
    --endpoint-url "$R2_ENDPOINT" \
    --recursive \
    | awk '{print $4}')

  # Check each R2 file to see if source still exists
  while IFS= read -r r2_file; do
    [ -z "$r2_file" ] && continue

    # Skip if it's a watermarked/thumb/preview file - we only check originals
    if echo "$r2_file" | grep -qE "_(watermarked|thumb|preview)\.(jpg|jpeg|png|gif|webp)$"; then
      continue
    fi

    # Construct expected source path
    local source_file="${SOURCE_DIR}/${r2_file}"

    if [ ! -f "$source_file" ]; then
      # Source file no longer exists, delete from R2
      log "  Deleting: $r2_file (source file removed)"

      # Delete original
      delete_from_r2 "$r2_file"

      # Delete associated files (watermarked, thumb, preview)
      local base_name="${r2_file%.*}"
      local ext="${r2_file##*.}"

      delete_from_r2 "${base_name}_watermarked.${ext}" 2>/dev/null
      delete_from_r2 "${base_name}_thumb.${ext}" 2>/dev/null
      delete_from_r2 "${base_name}_thumb.jpg" 2>/dev/null
      delete_from_r2 "${base_name}_preview.jpg" 2>/dev/null

      : $((deleted_count++))
    fi
  done <<< "$r2_files"

  log "Deleted $deleted_count file(s) from R2"
}