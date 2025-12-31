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
source "$SCRIPT_DIR/functions/watermark.sh"
source "$SCRIPT_DIR/functions/thumbnail.sh"
source "$SCRIPT_DIR/functions/upload.sh"
source "$SCRIPT_DIR/functions/catalog.sh"
source "$SCRIPT_DIR/functions/cleanup.sh"

# Create working directories if they don't exist
mkdir -p "$ORIG_DIR" "$WATER_DIR" "$THUMB_DIR" "$LOG_DIR"

# Logging function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Main execution
log "=== Starting gallery sync (Environment: $ENVIRONMENT) ==="

# Main execution
log "=== Starting gallery sync (Environment: $ENVIRONMENT) ==="

# Verify source directory exists and is accessible
if [ ! -d "$SOURCE_DIR" ]; then
  log "ERROR: Source directory not found: $SOURCE_DIR"
  exit 1
fi

# Count files to process
total_images=$(find "$SOURCE_DIR" -type f -regextype posix-extended -iregex ".*\.(${IMAGE_EXTS})" | wc -l)
log "Found $total_images images to process"

if [ $total_images -eq 0 ]; then
  log "No images found. Exiting."
  exit 0
fi

# Process each image
processed=0
failed=0

# Use process substitution instead of pipe to avoid subshell
while IFS= read -r img_file; do
  filename=$(basename "$img_file")
  name_no_ext="${filename%.*}"
  ext="${filename##*.}"

  log "Processing: $filename"

  # Copy original to working directory
  cp "$img_file" "$ORIG_DIR/$filename"

  # Generate watermarked version
  if generate_watermark "$ORIG_DIR/$filename" "$WATER_DIR/${name_no_ext}_watermarked.${ext}"; then
    # Upload watermarked version to R2
    if upload_to_r2 "$WATER_DIR/${name_no_ext}_watermarked.${ext}" "${name_no_ext}_watermarked.${ext}"; then
      ((processed++))
    else
      ((failed++))
    fi
  else
    ((failed++))
    continue
  fi

  # Generate thumbnail
  if generate_thumbnail "$ORIG_DIR/$filename" "$THUMB_DIR/${name_no_ext}_thumb.${ext}"; then
    # Upload thumbnail to R2
    upload_to_r2 "$THUMB_DIR/${name_no_ext}_thumb.${ext}" "${name_no_ext}_thumb.${ext}"
  else
    ((failed++))
  fi
done < <(find "$SOURCE_DIR" -type f -regextype posix-extended -iregex ".*\.(${IMAGE_EXTS})" | sort)

log "Processed: $processed | Failed: $failed"

# Generate JSON catalog
generate_catalog "$SOURCE_DIR" "$CATALOG_FILE"

# Push catalog to GitHub
push_catalog_to_github

# Cleanup temporary files
cleanup_temp_files

log "=== Gallery sync complete ==="

log "=== Gallery sync complete ==="