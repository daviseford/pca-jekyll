#!/bin/bash
# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

# Some constants to make this mroe portable
SITE_S3='s3://parkcenterautomotive.com/'
CSS_DIR='./public/css/'     # Constants
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
    uglifycss --ugly-comments ${file} > "${file/.css/.min.css}" # Create new minified CSS file
done
}

# Common tasks to consider automating
# Minifiers for JS

# Run this script with the "-i" flag to process images (takes longer)
if [ "$1" = "-i" ]; then
    run_image_tasks
fi

# Minify CSS (this modifies the CSS in the source files)
minify_css

# Build with Jekyll
bundle exec jekyll build

# Minify HTML (this modifies the generated HTML)
minify_html

# Upload to S3
if [ "$1" != "-n" ]; then
    aws s3 sync --delete --size-only ${SITE_DIR} ${SITE_S3}
fi

echo "Done!"