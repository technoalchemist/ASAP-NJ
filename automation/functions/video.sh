#!/bin/bash
#
# Video processing functions
#

extract_video_frame() {
  local video_file="$1"
  local output_file="$2"

  # Get video duration in seconds
  local duration=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)

  if [ -z "$duration" ]; then
    log "  ERROR: Could not determine video duration for $(basename "$video_file")"
    return 1
  fi

  # Check if video exceeds 3 minutes (180 seconds)
  local max_duration=180
  local duration_int=$(printf "%.0f" "$duration")

  if [ "$duration_int" -gt "$max_duration" ]; then
    log "  SKIPPED: Video exceeds 3-minute limit (${duration_int}s): $(basename "$video_file")"
    return 2  # Return 2 to indicate "skipped" vs "failed"
  fi

  # Calculate middle timestamp
  local middle=$(echo "$duration / 2" | bc)

  # Extract frame from middle of video
  ffmpeg -ss "$middle" -i "$video_file" -frames:v 1 -q:v 2 "$output_file" \
    -loglevel error 2>&1 | tee -a "$LOG_FILE"

  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log "  Extracted frame from video: $(basename "$video_file") (${duration_int}s)"
    return 0
  else
    log "  ERROR: Failed to extract frame from $(basename "$video_file")"
    return 1
  fi
}