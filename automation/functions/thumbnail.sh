#!/bin/bash
#
# Thumbnail generation functions
#

generate_thumbnail() {
  local input_file="$1"
  local output_file="$2"

  # Generate thumbnail with ImageMagick
  convert "$input_file" \
    -resize "${THUMB_SIZE}^" \
    -gravity center \
    -extent "$THUMB_SIZE" \
    "$output_file"

  if [ $? -eq 0 ]; then
    log "  Created thumbnail: $(basename "$output_file")"
    return 0
  else
    log "  ERROR: Failed to create thumbnail for $(basename "$input_file")"
    return 1
  fi
}
