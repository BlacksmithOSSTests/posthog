#!/bin/bash

# Find and duplicate each test file that ends with .test.js or .test.ts
find . -maxdepth 10 -type f \( -name "*.test.js" -o -name "*.test.ts" \) -exec bash -c '
  for file in "$@"; do
    # Extract the base name without test and the extension
    base="${file%.*}"         # Remove the last extension
    extension="${file##*.}"   # Get the last extension

    # Determine the test extension (js or ts)
    if [[ "${file}" == *.test.ts ]]; then
      test_extension="test.ts"
    else
      test_extension="test.js"
    fi

    # Construct the new filename and copy
    for i in $(seq 1 10); do
      cp "$file" "${base}_copy${i}.${test_extension}"
    done
  done
' _ {} +

