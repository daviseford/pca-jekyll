#!/bin/bash

# This renames .JPG, .jpeg, etc to .jpg
rename_pictures()
{
for file in `find ./public/images/ -name "*$1*" -type f`; do
  mv "$file" "${file/$1/$2}"
done
}

rename_pictures JPG jpg     # Renaming
rename_pictures jpeg jpg    # Renaming

# Compress images - uncomment to run
find ./public/images/ -type f -iname '*.jpg'  -exec jpegoptim --strip-com --max=85 {} \;
find ./public/images/ -type f -iname '*.png'  -print0 | xargs -0 optipng -o7

# Common tasks to consider automating
# Minifying HTML
# Minifiers for CSS and JS

# Build with Jekyll
bundle exec jekyll build

# Upload to S3
aws s3 sync --delete --size-only ./_site/ s3://parkcenterautomotive.com/

echo "Done!"