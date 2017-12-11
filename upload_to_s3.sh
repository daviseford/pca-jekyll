#!/bin/bash

# Compress images - uncomment to run
find ./public/images/ -type f -iname '*.jpg'  -exec jpegoptim --strip-com --max=85 {} \;
find ./public/images/ -type f -iname '*.JPG'  -exec jpegoptim --strip-com --max=85 {} \;
find ./public/images/ -type f -iname '*.jpeg'  -exec jpegoptim --strip-com --max=85 {} \;
find ./public/images/ -type f -iname '*.png'  -print0 | xargs -0 optipng -o7

# Build with Jekyll
bundle exec jekyll build

# Upload to S3
aws s3 sync --delete --size-only ./_site/ s3://parkcenterautomotive.com/