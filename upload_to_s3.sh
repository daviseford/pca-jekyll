#!/bin/bash
# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

# You can run this script with three options
# -i  | enable Image processing. Creates thumbnails, compresses images, and takes a while
# -n  | enable No-upload mode. Doesn't upload the build to S3.
# -s  | enable Setup mode. Downloads the necessary npm files for compression

# Some constants to make this more portable
SITE_S3='s3://parkcenterautomotive.com/'
CSS_DIR='./public/css/'     # Constants
JS_DIR='./public/js/'       # Constants
IMG_DIR='./public/images/'  # Constants
SITE_DIR='./_site/'         # Constants

# BUILD OPTIONS
MINIFY_CSS=true             # Minify any CSS in your CSS_DIR
MINIFY_JS=true              # Minify any JS files in your JS_DIR
MINIFY_HTML=true            # Minify the Jekyll-generated HTML in your SITE_DIR
COMPRESS_IMG=true           # If true, will compress all png and jpg files in your IMG_DIR
RENAME_IMG=true             # If true, will rename files in IMG_DIR from ".JPG" and ".jpeg" to ".jpg"

THUMBNAILS=false            # If true, will create a /thumbnails/ directory in your IMG_DIR
                            # with all of your current IMG_DIR structure copied over

FAVICONS=true               # If true, will generate favicon files for you
                            # Looks at /favicon.png and favicon_cfg.json
                            # Uses https://realfavicongenerator.net/ CLI tool

rename_pictures() # This renames files in our IMG_DIR
{
for file in `find ${IMG_DIR} -name "*$1*" -type f`; do
    mv "$file" "${file/$1/$2}"
done
}

run_image_tasks()
{
if [ "$RENAME_IMG" = true ] && [ -d "$IMG_DIR" ] ; then
    rename_pictures JPG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
    rename_pictures jpeg jpg    # jpeg -> jpg
    rename_pictures PNG png     # PNG  -> png
fi
if [ "$COMPRESS_IMG" = true ] && [ -d "$IMG_DIR" ] ; then # Compress images
    find ${IMG_DIR} -type f -iname '*.jpg'  -exec jpegoptim --strip-com --max=85 {} \;
    find ${IMG_DIR} -type f -iname '*.png'  -print0 | xargs -0 optipng -o7
fi
if [[ "$COMPRESS_IMG" = true || "$RENAME_IMG" = true ]] && [ -d "$IMG_DIR" ]; then
    echo "Ran image tasks"
fi
}

minify_html()
{
if [ "$MINIFY_HTML" = true ]  && [ -d "$SITE_DIR" ]; then
    # Using html-minifier | npm install html-minifier-cli -g
    for file in `find ${SITE_DIR} -name "*.html" -type f`; do
        htmlmin -o "${file}.min" "$file"  # Make a minified copy of each .html file
        mv "${file}.min" "$file"          # Overwrite the old HTML with the minified version
    done
    echo "Minified HTML"
fi
}

minify_css()
{
if [ "$MINIFY_CSS" = true ]  && [ -d "$CSS_DIR" ]; then
    # Using UglifyCSS | npm install uglifycss -g
    find ${CSS_DIR} -name "*.min.css" -type f|xargs rm -f   # Delete existing minified files
    for file in `find ${CSS_DIR} -name "*.css" -type f`; do
        uglifycss --ugly-comments --output "${file/.css/.min.css}" "$file" # Create minified CSS file
    done
    echo "Minified CSS"
fi
}

minify_js()
{
if [ "$MINIFY_JS" = true ] && [ -d "$JS_DIR" ]; then
    # Using google-closure-compiler-js | npm install google-closure-compiler-js -g
    find ${JS_DIR} -name "*.min.js" -type f|xargs rm -f   # Delete existing minified files
    for file in `find ${JS_DIR} -name "*.js" -type f`; do
        google-closure-compiler-js "$file" > "${file/.js/.min.js}"
    done
    echo "Minified JS"
fi
}

create_favicons()
{
if [ "$FAVICONS" = true ]; then
    if [ -f "favicon.png" ] && [ -f "favicon_cfg.json" ]; then # Make sure we have all our files
        # Using real-favicon | npm install cli-real-favicon -g
        real-favicon generate favicon_cfg.json f_report.json ${SITE_DIR}
        rm -f f_report.json
    else
        echo "Missing either favicon.png or favicon_cfg.json in the root directory of this site, can't generate thumbnails"
        fi
fi
}

create_thumbnails()
{
if [ "$THUMBNAILS" = true ] && [ -d "$IMG_DIR" ] ; then
    THUMBNAIL_DIR='/tmp/thumbnails/'
    # Google-recommended defaults
    # https://developers.google.com/speed/docs/insights/OptimizeImages
    JPG_OPTS='-resize 445 -sampling-factor 4:2:0'
    PNG_OPTS='-resize 445 -strip'
    rm -rf ${THUMBNAIL_DIR} && mkdir ${THUMBNAIL_DIR} # Housekeeping
    # Move images to /tmp/
    rsync -a --exclude '*thumbnails/*' ${IMG_DIR} ${THUMBNAIL_DIR}
    # Resize thumbs
    find ${THUMBNAIL_DIR} -type f -iname '*.jpg' -exec mogrify $JPG_OPTS {} \;
    # Move tmp thumbnails into the directory - only overwrite if size is different
    rsync -r --size-only --delete ${THUMBNAIL_DIR} "${IMG_DIR}thumbnails/"
    rm -rf ${THUMBNAIL_DIR} # Delete our temporary working directory
    echo "Created thumbnails"
fi
}

# Run setup
if [ "$1" = "-s" ] || [ "$2" = "-s" ] || [ "$3" = "-s" ]; then
    npm install google-closure-compiler-js -g
    npm install uglifycss -g
    npm install html-minifier-cli -g
    npm install cli-real-favicon -g
    exit 0
fi


# Run this script with the "-i" flag to process images (takes longer)
if [ "$1" = "-i" ] || [ "$2" = "-i" ] || [ "$3" = "-i" ]; then
    create_thumbnails && run_image_tasks
fi

# Minify CSS and JS source files - important to do this BEFORE building
minify_css && minify_js

# Build with Jekyll
bundle exec jekyll build

# Minify HTML (this modifies the generated HTML) - do AFTER building
minify_html

# Create favicons
create_favicons

# Upload to S3 - unless -n (no-upload) is passed in
if [ "$1" != "-n" ] && [ "$2" != "-n" ] && [ "$3" != "-n" ]; then
    aws s3 sync --delete --size-only ${SITE_DIR} ${SITE_S3} --exclude "*.sh"
    echo "Uploaded to S3"
fi

echo "Done!"