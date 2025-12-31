#!/bin/bash
#
# JSON catalog generation functions
#

generate_catalog() {
  local source_dir="$1"
  local catalog_file="$2"

  log "Generating JSON catalog..."

  # Start JSON structure
  echo "{" > "$catalog_file"
  echo '  "categories": {' >> "$catalog_file"

  local first_category=true

  # Process root-level files (General category)
  local root_files=$(find "$source_dir" -maxdepth 1 -type f -regextype posix-extended \
    -iregex ".*\.(${IMAGE_EXTS}|${VIDEO_EXTS})" | sort)

  if [ -n "$root_files" ]; then
    if [ "$first_category" = false ]; then
      echo "    ," >> "$catalog_file"
    fi
    first_category=false

    echo "    \"$ROOT_CATEGORY\": [" >> "$catalog_file"

    local first_item=true
    while IFS= read -r file; do
      [ -z "$file" ] && continue

      if [ "$first_item" = false ]; then
        echo "      ," >> "$catalog_file"
      fi
      first_item=false

      generate_catalog_entry "$file" "$catalog_file"
    done <<< "$root_files"

    echo "" >> "$catalog_file"
    echo "    ]" >> "$catalog_file"
  fi

  # Process subdirectories as categories
  find "$source_dir" -mindepth 1 -maxdepth 1 -type d | sort | while read -r category_dir; do
    local category_name=$(basename "$category_dir")
    local category_files=$(find "$category_dir" -maxdepth 1 -type f -regextype posix-extended \
      -iregex ".*\.(${IMAGE_EXTS}|${VIDEO_EXTS})" | sort)

    [ -z "$category_files" ] && continue

    if [ "$first_category" = false ]; then
      echo "    ," >> "$catalog_file"
    fi
    first_category=false

    echo "    \"$category_name\": [" >> "$catalog_file"

    local first_item=true
    while IFS= read -r file; do
      [ -z "$file" ] && continue

      if [ "$first_item" = false ]; then
        echo "      ," >> "$catalog_file"
      fi
      first_item=false

      generate_catalog_entry "$file" "$catalog_file"
    done <<< "$category_files"

    echo "" >> "$catalog_file"
    echo "    ]" >> "$catalog_file"
  done

  # Close JSON structure
  echo "" >> "$catalog_file"
  echo '  }' >> "$catalog_file"
  echo '}' >> "$catalog_file"

  log "Catalog generated: $catalog_file"
}

generate_catalog_entry() {
  local file="$1"
  local catalog_file="$2"

  local filename=$(basename "$file")
  local name_no_ext="${filename%.*}"
  local ext="${filename##*.}"

  # Get relative path from source dir (for folder structure)
  local rel_path=$(dirname "$file" | sed "s|^$SOURCE_DIR||" | sed 's|^/||')
  local r2_prefix=""
  [ -n "$rel_path" ] && r2_prefix="${rel_path}/"

  # Check if it's a video
  if echo "$filename" | grep -qiE "\.(${VIDEO_EXTS})$"; then
    # Video entry
    local video_url="${R2_PUBLIC_URL}/${r2_prefix}${filename}"
    local preview_url="${R2_PUBLIC_URL}/${r2_prefix}${name_no_ext}_preview.jpg"
    local thumb_url="${R2_PUBLIC_URL}/${r2_prefix}${name_no_ext}_thumb.jpg"

    cat >> "$catalog_file" << EOF
      {
        "filename": "$filename",
        "type": "video",
        "video": "$video_url",
        "preview": "$preview_url",
        "thumbnail": "$thumb_url"
      }
EOF
  else
    # Image entry
    local full_url="${R2_PUBLIC_URL}/${r2_prefix}${name_no_ext}_watermarked.${ext}"
    local thumb_url="${R2_PUBLIC_URL}/${r2_prefix}${name_no_ext}_thumb.${ext}"

    cat >> "$catalog_file" << EOF
      {
        "filename": "$filename",
        "type": "image",
        "full": "$full_url",
        "thumbnail": "$thumb_url"
      }
EOF
  fi
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