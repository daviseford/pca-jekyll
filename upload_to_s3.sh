#!/bin/bash

# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

rename_pictures() # This renames .JPG, .jpeg, etc to .jpg
{
for file in `find ./public/images/ -name "*$1*" -type f`; do
  mv "$file" "${file/$1/$2}"
done
}

run_image_tasks()
{
rename_pictures JPG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
rename_pictures jpeg jpg

# Compress images
find ./public/images/ -type f -iname '*.jpg'  -exec jpegoptim --strip-com --max=85 {} \;
find ./public/images/ -type f -iname '*.png'  -print0 | xargs -0 optipng -o7
}

# Common tasks to consider automating
# Minifying HTML
# Minifiers for CSS and JS

# Run this script with the "-i" flag to process images (takes longer)
if [ "$1" = "-i" ]; then
    run_image_tasks
fi

# Build with Jekyll
bundle exec jekyll build

# Upload to S3
aws s3 sync --delete --size-only ./_site/ s3://parkcenterautomotive.com/

echo "Done!"