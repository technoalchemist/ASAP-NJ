#!/bin/bash
#
# JSON catalog generation functions
#

generate_catalog() {
  local source_dir="$1"
  local catalog_file="$2"

  log "Generating JSON catalog..."

  # Extract account ID from R2 endpoint
  # Format: https://<account-id>.r2.cloudflarestorage.com
  local account_id=$(echo "$R2_ENDPOINT" | sed -n 's|https://\([^.]*\)\.r2\.cloudflarestorage\.com|\1|p')

  # Start JSON array
  echo "{" > "$catalog_file"
  echo '  "images": [' >> "$catalog_file"

  local first=true

  # Find all image files in source directory
  find "$source_dir" -type f -regextype posix-extended -iregex ".*\.(${IMAGE_EXTS})" | sort | while read -r img_file; do
    local filename=$(basename "$img_file")
    local name_no_ext="${filename%.*}"
    local ext="${filename##*.}"

    # R2 public URLs
    local full_url="https://pub-${account_id}.r2.dev/${name_no_ext}_watermarked.${ext}"
    local thumb_url="https://pub-${account_id}.r2.dev/${name_no_ext}_thumb.${ext}"

    # Add comma if not first entry
    if [ "$first" = false ]; then
      echo "    ," >> "$catalog_file"
    fi
    first=false

    # Add JSON entry
    cat >> "$catalog_file" << EOF
    {
      "filename": "$filename",
      "full": "$full_url",
      "thumbnail": "$thumb_url"
    }
EOF
  done

  # Close JSON array and object
  echo "" >> "$catalog_file"
  echo '  ]' >> "$catalog_file"
  echo '}' >> "$catalog_file"

  log "Catalog generated: $catalog_file"
}

push_catalog_to_github() {
  log "Pushing catalog to GitHub..."

  cd "$REPO_DIR"

  # Add and commit catalog
  git add docs/gallery-data.json
  git commit -m "Update gallery catalog - $(date '+%Y-%m-%d %H:%M:%S')" || {
    log "No changes to commit"
    return 0
  }

  # Push to remote
  git push origin $(git branch --show-current)

  if [ $? -eq 0 ]; then
    log "Catalog pushed to GitHub"
    return 0
  else
    log "ERROR: Failed to push catalog to GitHub"
    return 1
  fi
}