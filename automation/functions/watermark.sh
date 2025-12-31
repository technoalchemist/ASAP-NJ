#!/bin/bash
#
# Watermark generation functions
#

generate_watermark() {
  local input_file="$1"
  local output_file="$2"

  # Calculate font size based on image height
  local img_height=$(identify -format "%h" "$input_file")
  local font_size=$((img_height * $WATERMARK_SIZE / 1000))

  # Generate watermarked image
  convert "$input_file" \
    -gravity SouthEast \
    -font "$WATERMARK_FONT" \
    -pointsize "$font_size" \
    -fill "rgba(255,255,255,0.${WATERMARK_OPACITY})" \
    -stroke "rgba(0,0,0,0.3)" \
    -strokewidth 1 \
    -annotate +20+20 "$WATERMARK_TEXT" \
    "$output_file"

  if [ $? -eq 0 ]; then
    log "  Created watermark: $(basename "$output_file")"
    return 0
  else
    log "  ERROR: Failed to watermark $(basename "$input_file")"
    return 1
  fi
}