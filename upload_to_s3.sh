#!/bin/bash
# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

# Some constants to make this mroe portable
SITE_S3='s3://parkcenterautomotive.com/'
CSS_DIR='./public/css/'     # Constants
JS_DIR='./public/js/'       # Constants
IMG_DIR='./public/images/'  # Constants
SITE_DIR='./_site/'         # Constants

rename_pictures() # This renames .JPG, .jpeg, etc to .jpg
{
for file in `find ${IMG_DIR} -name "*$1*" -type f`; do
    mv ${file} "${file/$1/$2}"
done
}

run_image_tasks()
{
rename_pictures JPG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
rename_pictures jpeg jpg

# Compress images
find ${IMG_DIR} -type f -iname '*.jpg'  -exec jpegoptim --strip-com --max=85 {} \;
find ${IMG_DIR} -type f -iname '*.png'  -print0 | xargs -0 optipng -o7
}

# Using html-minifier | npm install html-minifier-cli -g
minify_html()
{
TMP_EXT='.min'
for file in `find ${SITE_DIR} -name "*.html" -type f`; do
    htmlmin -o "${file}${TMP_EXT}" ${file}  # Make a minified copy of each .html file
done
# Now overwrite the older HTML with the new, minified version
for file in `find ${SITE_DIR} -name "*${TMP_EXT}" -type f`; do
    FILE_EXT="html${TMP_EXT}"
    mv ${file} "${file/$FILE_EXT/html}"
done
}

minify_css()
{
find ${CSS_DIR} -name "*.min.css" -type f|xargs rm -f   # Delete existing minified files
# Using Uglify - npm install uglifycss -g
for file in `find ${CSS_DIR} -name "*.css" -type f`; do
    uglifycss --ugly-comments --output "${file/.css/.min.css}" ${file} # Create minified CSS file
done
}

minify_js()
{
find ${JS_DIR} -name "*.min.js" -type f|xargs rm -f   # Delete existing minified files
# npm install uglify-es -g
for file in `find ${JS_DIR} -name "*.js" -type f`; do
    uglifyjs ${file} --compress --mangle -o "${file/.js/.min.js}"
done
}

create_thumbnails()
{
THUMBNAIL_DIR='/tmp/thumbnails/'
# Google-recommended defaults
# https://developers.google.com/speed/docs/insights/OptimizeImages
JPG_OPTS='-resize 445 -sampling-factor 4:2:0'
PNG_OPTS='-resize 445 -strip'
rm -rf ${THUMBNAIL_DIR} # Housekeeping
mkdir ${THUMBNAIL_DIR}  # Housekeeping
# Move images to /tmp/
rsync -a --exclude '*thumbnails/*' ${IMG_DIR} ${THUMBNAIL_DIR}
# Resize thumbs
find ${THUMBNAIL_DIR} -type f -iname '*.jpg' -exec mogrify $JPG_OPTS {} \;
# Move tmp thumbnails into the directory - only overwrite if size is different
rsync -r --size-only --delete ${THUMBNAIL_DIR} "${IMG_DIR}thumbnails/"
rm -rf ${THUMBNAIL_DIR}
}

# Run this script with the "-i" flag to process images (takes longer)
if [ "$1" = "-i" ] || [ "$2" = "-i" ]; then
    run_image_tasks
    echo "Ran image tasks"
#    create_thumbnails
#    echo "Created thumbnails"
fi

# Minify CSS and JS source files
minify_css
minify_js
echo "Minified CSS and JS"

# Build with Jekyll
bundle exec jekyll build

# Minify HTML (this modifies the generated HTML)
minify_html
echo "Minified HTML"

# Upload to S3
if [ "$1" != "-n" ] && [ "$2" != "-n" ]; then
    aws s3 sync --delete --size-only ${SITE_DIR} ${SITE_S3}
    echo "Uploaded to S3"
fi

echo "Done!"