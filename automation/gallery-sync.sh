#!/bin/bash
#
# ASAP-NJ Gallery Sync
# Syncs images from Windows share to R2 CDN with watermarking
# Author: TechnoAlchemist
# Version: 3.0.0
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Lockfile to prevent concurrent runs
LOCKFILE="/tmp/gallery-sync.lock"

# Check for lockfile
if [ -f "$LOCKFILE" ]; then
  echo "$(date): Previous sync still running. Exiting."
  exit 0
fi

# Create lockfile
touch "$LOCKFILE"

# Ensure lockfile is removed on exit
trap "rm -f $LOCKFILE" EXIT

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
source "$SCRIPT_DIR/config/gallery.conf"

# Source R2 credentials
source "$R2_CREDS"

# Source functions
source "$SCRIPT_DIR/functions/catalog.sh"
source "$SCRIPT_DIR/functions/cleanup.sh"
source "$SCRIPT_DIR/functions/sync.sh"
source "$SCRIPT_DIR/functions/thumbnail.sh"
source "$SCRIPT_DIR/functions/upload.sh"
source "$SCRIPT_DIR/functions/video.sh"
source "$SCRIPT_DIR/functions/watermark.sh"

# Create working directories if they don't exist
mkdir -p "$ORIG_DIR" "$WATER_DIR" "$THUMB_DIR" "$LOG_DIR"

# Logging function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Main execution
log "=== Starting gallery sync (Environment: $ENVIRONMENT) ==="

# Verify source directory exists and is accessible
if [ ! -d "$SOURCE_DIR" ]; then
  log "ERROR: Source directory not found: $SOURCE_DIR"
  exit 1
fi

# Count files to process
total_images=$(find "$SOURCE_DIR" -type f -regextype posix-extended -iregex ".*\.(${IMAGE_EXTS})" | wc -l)
total_videos=$(find "$SOURCE_DIR" -type f -regextype posix-extended -iregex ".*\.(${VIDEO_EXTS})" | wc -l)
total_files=$((total_images + total_videos))

log "Found $total_images images and $total_videos videos to process"

if [ $total_files -eq 0 ]; then
  log "No files found. Exiting."
  exit 0
fi

# Process
failed=0
processed=0
skipped=0

# Process all files (images and videos) recursively
while IFS= read -r file; do
  filename=$(basename "$file")
  name_no_ext="${filename%.*}"
  ext="${filename##*.}"

  # Get relative path from source dir (for folder structure in R2)
  rel_path=$(dirname "$file" | sed "s|^$SOURCE_DIR||" | sed 's|^/||')
  r2_prefix=""
  [ -n "$rel_path" ] && r2_prefix="${rel_path}/"

  # Check if file needs processing (change detection)
  if ! needs_processing "$file" "${r2_prefix}${filename}"; then
    log "  Skipping (already processed): ${r2_prefix}${filename}"
    continue
  fi

  log "Processing: ${r2_prefix}${filename}"

  # Check if it's a video
  if echo "$filename" | grep -qiE "\.(${VIDEO_EXTS})$"; then
    # Process video
    cp "$file" "$ORIG_DIR/$filename"

    # Extract frame from middle of video (returns 2 if video too long)
    extract_result=0
    extract_video_frame "$ORIG_DIR/$filename" "$WORK_DIR/frame_${name_no_ext}.jpg" || extract_result=$?

    if [ $extract_result -eq 2 ]; then
      # Video too long, skip
      : $((skipped++))
      rm -f "$ORIG_DIR/$filename"
      continue
    elif [ $extract_result -ne 0 ]; then
      # Extraction failed
      : $((failed++))
      rm -f "$ORIG_DIR/$filename"
      continue
    fi

    # Watermark the extracted frame
    if generate_watermark "$WORK_DIR/frame_${name_no_ext}.jpg" "$WATER_DIR/${name_no_ext}_preview.jpg"; then
      # Generate thumbnail from watermarked frame
      if generate_thumbnail "$WATER_DIR/${name_no_ext}_preview.jpg" "$THUMB_DIR/${name_no_ext}_thumb.jpg"; then
        # Upload all three: original video, preview, thumbnail
        upload_to_r2 "$ORIG_DIR/$filename" "${r2_prefix}${filename}" && \
          upload_to_r2 "$WATER_DIR/${name_no_ext}_preview.jpg" "${r2_prefix}${name_no_ext}_preview.jpg" && \
          upload_to_r2 "$THUMB_DIR/${name_no_ext}_thumb.jpg" "${r2_prefix}${name_no_ext}_thumb.jpg"

        if [ $? -eq 0 ]; then
          : $((processed++))
        else
          : $((failed++))
        fi
      else
        : $((failed++))
      fi
    else
      : $((failed++))
    fi

    # Clean up temp frame
    rm -f "$WORK_DIR/frame_${name_no_ext}.jpg"
  else
    # Process image (existing logic with change detection)
    cp "$file" "$ORIG_DIR/$filename"

    if generate_watermark "$ORIG_DIR/$filename" "$WATER_DIR/${name_no_ext}_watermarked.${ext}"; then
      if upload_to_r2 "$WATER_DIR/${name_no_ext}_watermarked.${ext}" "${r2_prefix}${name_no_ext}_watermarked.${ext}"; then
        : $((processed++))
      else
        : $((failed++))
      fi
    else
      : $((failed++))
      continue
    fi

    if generate_thumbnail "$ORIG_DIR/$filename" "$THUMB_DIR/${name_no_ext}_thumb.${ext}"; then
      upload_to_r2 "$THUMB_DIR/${name_no_ext}_thumb.${ext}" "${r2_prefix}${name_no_ext}_thumb.${ext}"
    else
      : $((failed++))
    fi
  fi
done < <(find "$SOURCE_DIR" -type f -regextype posix-extended -iregex ".*\.(${IMAGE_EXTS}|${VIDEO_EXTS})" | sort)

log "Processed: $processed | Failed: $failed | Skipped: $skipped"

# Sync deletions
sync_deletions

# Generate JSON catalog
generate_catalog "$SOURCE_DIR" "$CATALOG_FILE"

# Push catalog to GitHub
push_catalog_to_github

# Cleanup temporary files
cleanup_temp_files

log "=== Gallery sync complete ==="