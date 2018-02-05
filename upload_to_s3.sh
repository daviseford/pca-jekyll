#!/bin/bash
# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

# You can run this script with three options
# -i  | enable Image processing. Creates thumbnails and quickly compresses images.
# -c  | enable maximum Compression for images. Creates thumbnails, thoroughly compresses images, and takes a long time doing it
# -n  | No-upload mode. Doesn't upload the build to S3.
# -s  | enable Setup mode. Downloads the necessary npm files for compression

# BUILD OPTIONS - EDIT THESE
SITE_S3='s3://parkcenterautomotive.com/'    # Your S3 bucket address
CSS_DIR='./_site/public/css/'   # Constants
IMG_DIR='./public/images/'         # Constants
JS_DIR='./_site/public/js/'     # Constants
SITE_OUTPUT_DIR='./_site/'      # Constants

# BUILD OPTIONS - EDIT THESE
MINIFY_CSS=true             # Minify any CSS in your CSS_DIR
MINIFY_JS=true              # Minify any JS files in your JS_DIR
BABELIFY_JS=true            # Babelify any JS files in your JS_DIR
MINIFY_HTML=true            # Minify the Jekyll-generated HTML in your SITE_DIR
COMPRESS_IMG=true           # If true, will compress all png and jpg files in the IMG_DIR
RENAME_IMG=true             # If true, will rename files in IMG_DIR from ".JPG" and ".jpeg" to ".jpg"
THUMBNAILS=false            # If true, will create a /thumbnails/ directory in your IMG_DIR
                            # with all of your current IMG_DIR structure copied over

FAVICONS=true               # If true, will generate favicon files for you
                            # Looks at /favicon.png and favicon_cfg.json
                            # Uses https://realfavicongenerator.net/ CLI tool

# END EDITING. DO NOT EDIT PAST THIS POINT.

# CLI OPTIONS - WILL BE SET AUTOMATICALLY. DO NOT TOUCH
ARG_I=false
ARG_C=false
ARG_N=false
ARG_S=false
COMPRESSION_LEVEL="-o1"
BUILD_LOG="build_log.txt"
IMG_THUMB_DIR="${IMG_DIR}thumbnails/"
TMP_THUMB_DIR='/tmp/thumbnails/'
TMP_THUMB_DIR2='/tmp/thumbnails_tmp/'
JPG_OPTS='-resize 445 -sampling-factor 4:2:0' # Will be used by mogrify
PNG_OPTS='445'  # Will be used by imagemagick's convert
# https://stackoverflow.com/questions/3953645/ternary-operator-in-bash
PREVIOUS_BUILD_TIMESTAMP=$([ -f "$BUILD_LOG" ] && echo `stat -f"%Sm" -t "%F %T" "$BUILD_LOG"` || echo "1989-05-22 23:59:59")

# Setting options using getopts
while getopts :icnsz: opt; do   # Extra parameter argument (z) is apparently necessary to loop over all options. I don't know why
  case $opt in
    i)  # Image processing
      ARG_I=true
    ;;
    c)  # Compression
      ARG_I=true # Implicit invocation
      ARG_C=true
      COMPRESSION_LEVEL="-o7"
    ;;
    n)  # No upload
      ARG_N=true
    ;;
    s)  # Setup
      ARG_S=true
    ;;
    \?) # Error
      echo "Bad parameter: -i, -c, -n, -s are accepted"
      exit 1
    ;;
  esac
done


# BEGINNING OF BULK OF THE PROGRAM
write_build_log()
{
    current_timestamp=`date '+%Y-%m-%d %H:%M:%S'`
    echo "Built $current_timestamp" > "$BUILD_LOG"
    echo "Created $BUILD_LOG"
}

rename_extension() # This renames files in our IMG_DIR
{
for file in `find ${IMG_DIR} -name "*.$1" -type f`; do
    mv "$file" "${file/.$1/.$2}"
done
}

run_image_tasks()
{
if [ "$RENAME_IMG" = true ] && [ -d "$IMG_DIR" ] ; then
    rename_extension JPG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
    rename_extension JPEG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
    rename_extension jpeg jpg    # jpeg -> jpg
    rename_extension PNG png     # PNG  -> png
fi

if [ "$COMPRESS_IMG" = true ] && [ -d "$IMG_DIR" ] ; then # Compress images
    # Only compress if there are new files
    N_JPG=`find ${IMG_DIR} -not -path '*thumbnails/*' -type f -iname '*.jpg' -newerct "$PREVIOUS_BUILD_TIMESTAMP" | wc -l | xargs` # Number of files that meet this criteria
    N_PNG=`find ${IMG_DIR} -not -path '*thumbnails/*' -type f -iname '*.png' -newerct "$PREVIOUS_BUILD_TIMESTAMP" | wc -l | xargs`
    if [ "$N_JPG" -gt 0 ]; then
        echo "Now compressing ${N_JPG} jpg files in ${IMG_DIR}"
        find "$IMG_DIR" -not -path '*thumbnails/*' -type f -iname '*.jpg' -newerct "$PREVIOUS_BUILD_TIMESTAMP" -exec jpegoptim --strip-com --quiet --max=85 {} \;
    fi
    if [ "$N_PNG" -gt 0 ]; then
        echo "Now running ${COMPRESSION_LEVEL} level compression on ${N_PNG} .png files in ${IMG_DIR}"
        find ${IMG_DIR} -not -path '*thumbnails/*' -type f -iname '*.png' -newermt "$PREVIOUS_BUILD_TIMESTAMP" -print0 | xargs -0 optipng "$COMPRESSION_LEVEL" -silent # Takes so long
    fi
fi

if [[ "$ARG_I" = true ]] && [ -d "$IMG_DIR" ]; then
    echo "Finished image tasks"
fi
}

minify_html()   # Using html-minifier | npm install html-minifier-cli -g
{
if [ "$MINIFY_HTML" = true ]  && [ -d "$SITE_OUTPUT_DIR" ]; then
    for file in `find ${SITE_OUTPUT_DIR} -name "*.html" -type f`; do
        htmlmin -o "${file}.min" "$file"  # Make a minified copy of each .html file
        mv "${file}.min" "$file"          # Overwrite the old HTML with the minified version
    done
    echo "Minified HTML"
fi
}

minify_css()    # Using UglifyCSS | npm install uglifycss -g
{
if [ "$MINIFY_CSS" = true ]  && [ -d "$CSS_DIR" ]; then
    find ${CSS_DIR} -name "*.min.css" -type f|xargs rm -f   # Delete existing minified files
    for file in `find ${CSS_DIR} -name "*.css" -type f`; do
        uglifycss --ugly-comments --output "${file/.css/.min.css}" "$file" # Create minified CSS file
    done
    echo "Minified CSS"
fi
}

minify_js()     # Using google-closure-compiler-js | npm install google-closure-compiler-js -g
{
if [ "$MINIFY_JS" = true ] && [ -d "$JS_DIR" ]; then
    find ${JS_DIR} -name "*.min.js" -type f|xargs rm -f   # Delete existing minified files
    for file in `find ${JS_DIR} -name "*.js" -type f`; do
        google-closure-compiler-js "$file" > "${file/.js/.min.js}"
    done
    echo "Minified JS"
fi
}

babelify_js()
{
if [ "$BABELIFY_JS" = true ] && [ -d "$JS_DIR" ]; then
    # We use the npm-g root trick to load global presets for Babel
    for file in `find ${JS_DIR} -name "*.js" -type f -not -name "*.min.js"`; do
        npx babel "$file" --presets "$(npm -g root)/babel-preset-env" --out-file "$file"
    done
    echo "Babelified JS"
fi
}

create_favicons()   # Using real-favicon | npm install cli-real-favicon -g
{
if [ "$FAVICONS" = true ]; then
    if [ -f "favicon.png" ] && [ -f "favicon_cfg.json" ]; then # Make sure we have all our files
        real-favicon generate favicon_cfg.json f_report.json ${SITE_OUTPUT_DIR}
        rm -f f_report.json
    else
        echo "Missing either favicon.png or favicon_cfg.json in the root directory of this site, can't generate thumbnails"
    fi
fi
}

create_thumbnails()
{
if [ "$THUMBNAILS" = true ] && [ -d "$IMG_DIR" ] ; then
    rm -rf ${TMP_THUMB_DIR} && mkdir ${TMP_THUMB_DIR}  # Housekeeping
    rm -rf ${TMP_THUMB_DIR2} && mkdir ${TMP_THUMB_DIR2}  # Housekeeping
    find ${IMG_THUMB_DIR} -name '*.DS_Store' -type f -delete # Delete pesky .DS_Store files
    rsync -a --exclude '*thumbnails/*' --exclude '.DS_Store' ${IMG_DIR} ${TMP_THUMB_DIR}  # Move images to /tmp/
    EXISTING_FILE_COUNT=`find ${TMP_THUMB_DIR} -type f | wc -l | xargs`

    # A.) Check that the file has an associated thumbnail file in our IMG_THUMBDIR
    # B.) If it does, just copy that file to our TMP_DIR2
    # C.) If it doesn't, resize and compress
    find ${TMP_THUMB_DIR} -type f -not -newermt "$PREVIOUS_BUILD_TIMESTAMP" | while read file; do
        FILEPATH="${file/${TMP_THUMB_DIR}\//}"
        DIRNAME=$( dirname "$FILEPATH" )
        DEST="$TMP_THUMB_DIR2$FILEPATH"
        MKDIR="$TMP_THUMB_DIR2$DIRNAME"
        ORIG_THUMB_PATH="$IMG_THUMB_DIR$FILEPATH"
        if [ -f "$ORIG_THUMB_PATH" ]; then # File exists already, just copy it to $DEST, and delete the file in our TMP_THUMB_DIR
            mkdir -p "$MKDIR" && mv "$ORIG_THUMB_PATH" "$DEST" && rm -f "$file"
        fi
    done

    NEW_FILE_COUNT=`find ${TMP_THUMB_DIR} -type f | wc -l | xargs`

    # Resize thumbs
    find ${TMP_THUMB_DIR} -type f -iname '*.jpg' -exec mogrify $JPG_OPTS {} \;
    find ${TMP_THUMB_DIR} -type f -iname '*.png' -exec convert \{} -resize $PNG_OPTS\> \{} \;

    # Further compress thumbnails
    find ${TMP_THUMB_DIR} -type f -iname '*.jpg' -exec jpegoptim --strip-com --quiet --max=85 {} \;
    find ${TMP_THUMB_DIR} -type f -iname '*.png' -print0 | xargs -0 optipng -o7 -silent # Takes so long

    # Move the old thumbnails (already compressed) back into our dir
    rsync -r --size-only ${TMP_THUMB_DIR2} ${TMP_THUMB_DIR}

    # Move TMP_THUMB_DIR thumbnails into the IMG_THUMB_DIR directory - only overwrite if size is different
    rsync -r --size-only --delete ${TMP_THUMB_DIR} ${IMG_THUMB_DIR}
    rm -rf ${TMP_THUMB_DIR} && rm -rf ${TMP_THUMB_DIR2} # Delete our temporary working directories
    echo "Generated $EXISTING_FILE_COUNT thumbnails ($NEW_FILE_COUNT new) in ${IMG_THUMB_DIR}"
fi
}

### START OF EXECUTION ###
# Run setup
if [ "$ARG_S" = true ]; then
    echo "Installing dependencies..."
    brew install imagemagick
    brew upgrade imagemagick
    npm install babel-cli -g
    npm install babel-preset-env -g
    npm install google-closure-compiler-js -g
    npm install uglifycss -g
    npm install html-minifier-cli -g
    npm install cli-real-favicon -g
    echo "Dependencies installed."
fi

# Run this script with the "-i" flag to process images (takes longer)
if [ "$ARG_I" = true ]; then
    create_thumbnails && run_image_tasks
fi

# Build with Jekyll
bundle exec jekyll build

# Babelify/Minify Javascript
babelify_js && minify_js

#Minify CSS/HTML
minify_css && minify_html

# Create favicons
create_favicons

# Upload to S3 - unless -n (no-upload) is passed in
if [ "$ARG_N" = false ]; then
    aws s3 sync --delete --size-only ${SITE_OUTPUT_DIR} ${SITE_S3} --exclude "*build_log.txt" --exclude "*.idea*" --exclude "*.sh" --exclude "*.git*" --exclude "*.DS_Store"
    echo "Uploaded to S3"
fi

# Write our build log
if [ "$ARG_I" = true ] && [ "$ARG_C" = true ]; then
    write_build_log
fi

echo "Done!"