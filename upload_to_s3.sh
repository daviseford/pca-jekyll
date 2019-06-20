#!/bin/bash
# This script does some various utility tasks
# Builds the static site using Jekyll
# And syncs the generated site with S3

# You can run this script with three options
# -i  | enable Image processing. Creates thumbnails and quickly compresses images.
# -c  | enable maximum Compression for images. Creates thumbnails, thoroughly compresses images, and takes a long time doing it
# -n  | No-upload mode. Doesn't upload the build to S3.
# -s  | enable Setup mode. Downloads the necessary npm files for compression.
# -r  | Reload Cloudfront Cache (invalidates the cache, so the latest changes are shown).

# BUILD OPTIONS - EDIT THESE
SITE_S3='s3://parkcenterautomotive.com/'        # Your S3 bucket address
SITE_BUILD_DIR='./_site/'                       # Where your site is generated
CSS_BUILD_DIR="${SITE_BUILD_DIR}/public/css/"   # Generated CSS location
JS_BUILD_DIR="${SITE_BUILD_DIR}/public/js/"     # Generated JS location

SITE_SRC_DIR="./public/"
CSS_SRC_DIR="${SITE_SRC_DIR}css/"               # Source CSS
JS_SRC_DIR="${SITE_SRC_DIR}js/"                 # Source JS
IMG_SRC_DIR="${SITE_SRC_DIR}images/"            # Source images

CF_DIST_ID='E3N38VVPZOP07M'                     # Cloudfront Distribution ID
CF_PATH='/*'                                    # Cloudfront Path to invalidate

# BUILD OPTIONS - EDIT THESE
IS_JEKYLL_SITE=true         # If true, will run jekyll build process

MINIFY_BUILD_CSS=true       # Minify any CSS in your CSS_BUILD_DIR
MINIFY_BUILD_JS=true        # Minify any JS files in your JS_BUILD_DIR
BABELIFY_BUILD_JS=true      # Babelify any JS files in your JS_BUILD_DIR

MINIFY_SRC_CSS=true         # Minify any CSS in your CSS_SRC_DIR
MINIFY_SRC_JS=true          # Minify any JS files in your JS_SRC_DIR

MINIFY_HTML=true            # Minify the Jekyll-generated HTML in your SITE_BUILD_DIR
COMPRESS_IMG=true           # If true, will compress all png and jpg files in the IMG_SRC_DIR
RENAME_IMG=true             # If true, will rename files in IMG_SRC_DIR from ".JPG" and ".jpeg" to ".jpg"
THUMBNAILS=false            # If true, will create a /thumbnails/ directory in your IMG_SRC_DIR
                            # with all of your current IMG_SRC_DIR structure copied over

FAVICONS=true               # If true, will generate favicon files for you
                            # Looks at /favicon.png and favicon_cfg.json
                            # Uses https://realfavicongenerator.net/ CLI tool

# END EDITING. DO NOT EDIT PAST THIS POINT.

# CLI OPTIONS - WILL BE SET AUTOMATICALLY. DO NOT TOUCH
ARG_I=false
ARG_C=false
ARG_N=false
ARG_R=false
ARG_S=false
COMPRESSION_LEVEL="-o1"
BUILD_LOG="build_log.txt"
IMG_THUMB_DIR="${IMG_SRC_DIR}thumbnails/"
TMP_THUMB_DIR='/tmp/thumbnails/'
TMP_THUMB_DIR2='/tmp/thumbnails_tmp/'
JPG_OPTS='-resize 445 -sampling-factor 4:2:0' # Will be used by mogrify
PNG_OPTS='445'  # Will be used by imagemagick's convert
# https://stackoverflow.com/questions/3953645/ternary-operator-in-bash
PREVIOUS_BUILD_TIMESTAMP=$([ -f "$BUILD_LOG" ] && echo `stat -f"%Sm" -t "%F %T" "$BUILD_LOG"` || echo "1989-05-22 23:59:59")

# Setting options using getopts
while getopts :icnrsz: opt; do   # Extra parameter argument (z) is apparently necessary to loop over all options. I don't know why
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
    r)  # Reload Cloudfront Cache
      ARG_R=true
    ;;
    s)  # Setup
      ARG_S=true
    ;;
    \?) # Error
      echo "Bad parameter: -i, -c, -n, -r, -s are accepted"
      exit 1
    ;;
  esac
done


# BEGINNING OF BULK OF THE PROGRAM
make_site_output_dir()
{
    rm -rf ${SITE_BUILD_DIR}
    mkdir -p ${SITE_BUILD_DIR}
}

make_tmp_dirs()
{
    rm -rf ${TMP_THUMB_DIR}
    rm -rf ${TMP_THUMB_DIR2}
    mkdir -p ${TMP_THUMB_DIR}
    mkdir -p ${TMP_THUMB_DIR2}
}

move_to_output_dir()
{
    rsync -az ${SITE_SRC_DIR} ${SITE_BUILD_DIR} --exclude "${SITE_BUILD_DIR}*" --exclude "*.idea*" --exclude "*.sh" --exclude "*.git*" --exclude "*.DS_Store"
    echo "Moved files to ${SITE_BUILD_DIR}"
}

write_build_log()
{
    current_timestamp=`date '+%Y-%m-%d %H:%M:%S'`
    echo "Built $current_timestamp" > "$BUILD_LOG"
    echo "Created $BUILD_LOG"
}

rename_extension() # This renames files in our IMG_DIR
{
for file in `find ${IMG_SRC_DIR} -name "*.$1" -type f`; do
    mv "$file" "${file/.$1/.$2}"
done
}

run_image_tasks()
{
if [ "$RENAME_IMG" = true ] && [ -d "$IMG_SRC_DIR" ] ; then
    rename_extension JPG jpg     # Renaming JPG -> jpg (makes the below optimization faster)
    rename_extension JPEG jpg    # Renaming JPG -> jpg (makes the below optimization faster)
    rename_extension jpeg jpg    # jpeg -> jpg
    rename_extension PNG png     # PNG  -> png
fi

if [ "$COMPRESS_IMG" = true ] && [ -d "$IMG_SRC_DIR" ] ; then # Compress images
    # Only compress if there are new files
    N_JPG=`find ${IMG_SRC_DIR} -not -path '*thumbnails/*' -type f -iname '*.jpg' -newerct "$PREVIOUS_BUILD_TIMESTAMP" | wc -l | xargs` # Number of files that meet this criteria
    N_PNG=`find ${IMG_SRC_DIR} -not -path '*thumbnails/*' -type f -iname '*.png' -newerct "$PREVIOUS_BUILD_TIMESTAMP" | wc -l | xargs`
    if [ "$N_JPG" -gt 0 ]; then
        echo "Now compressing ${N_JPG} jpg files in ${IMG_SRC_DIR}"
        find "$IMG_SRC_DIR" -not -path '*thumbnails/*' -type f -iname '*.jpg' -newerct "$PREVIOUS_BUILD_TIMESTAMP" -exec jpegoptim --strip-com --quiet --max=85 {} \;
    fi
    if [ "$N_PNG" -gt 0 ]; then
        echo "Now running ${COMPRESSION_LEVEL} level compression on ${N_PNG} .png files in ${IMG_SRC_DIR}"
        find ${IMG_SRC_DIR} -not -path '*thumbnails/*' -type f -iname '*.png' -newermt "$PREVIOUS_BUILD_TIMESTAMP" -print0 | xargs -0 optipng "$COMPRESSION_LEVEL" -silent # Takes so long
    fi
fi

if [[ "$ARG_I" = true ]] && [ -d "$IMG_SRC_DIR" ]; then
    echo "Finished image tasks"
fi
}

minify_build_html()   # Using html-minifier | npm install html-minifier-cli -g
{
if [ "$MINIFY_HTML" = true ]  && [ -d "$SITE_BUILD_DIR" ]; then
    for file in `find ${SITE_BUILD_DIR} -name "*.html" -type f`; do
        htmlmin -o "${file}.min" "$file"  # Make a minified copy of each .html file
        mv "${file}.min" "$file"          # Overwrite the old HTML with the minified version
    done
    echo "Minified HTML"
fi
}

minify_src_css()    # Using UglifyCSS | npm install uglifycss -g
{
if [ "$MINIFY_SRC_CSS" = true ]  && [ -d "$CSS_SRC_DIR" ]; then
    for file in `find ${CSS_SRC_DIR} -name "*.css" -type f -not -name "*.min.css"`; do
        if [ -f "${file/.css/.min.css}" ]; then
            rm -f "${file/.css/.min.css}"   # Remove previous versions
        fi
        uglifycss --ugly-comments --output "${file/.css/.min.css}" "$file" # Create minified CSS file
    done
    echo "Minified source CSS"
fi
}

minify_build_css()
{
if [ "$MINIFY_BUILD_CSS" = true ]  && [ -d "$CSS_BUILD_DIR" ]; then
    for file in `find ${CSS_BUILD_DIR} -name "*.css" -type f -not -name "*.min.css"`; do
        if [ -f "${file/.css/.min.css}" ]; then
            rm -f "${file/.css/.min.css}"   # Remove previous versions
        fi
        uglifycss --ugly-comments --output "${file/.css/.min.css}" "$file"
    done
    echo "Minified build CSS"
fi
}

minify_src_js()     # Using google-closure-compiler | npm install google-closure-compiler -g
{
if [ "$MINIFY_SRC_JS" = true ] && [ -d "$JS_SRC_DIR" ]; then
    for file in `find ${JS_SRC_DIR} -name "*.js" -type f -not -name "*.min.js"`; do
        if [ -f "${file/.js/.min.js}" ]; then
            rm -f "${file/.js/.min.js}"   # Remove previous version
        fi
        npx google-closure-compiler "$file" > "${file/.js/.min.js}"
    done
    echo "Minified source JS"
fi
}

minify_build_js()
{
if [ "$MINIFY_BUILD_JS" = true ] && [ -d "$JS_BUILD_DIR" ]; then
    for file in `find ${JS_BUILD_DIR} -name "*.js" -type f -not -name "*.min.js"`; do
        if [ -f "${file/.js/.min.js}" ]; then
            rm -f "${file/.js/.min.js}"   # Remove previous version
        fi
        npx google-closure-compiler "$file" > "${file/.js/.min.js}"
    done
    echo "Minified build JS"
fi
}

babelify_build_js()
{
if [ "$BABELIFY_BUILD_JS" = true ] && [ -d "$JS_BUILD_DIR" ]; then
    for file in `find ${JS_BUILD_DIR} -name "*.js" -type f -not -name "*.min.js"`; do
        npx babel "$file" --presets "$(npm -g root)/babel-preset-env" --out-file "$file"
    done
    echo "Babelified build JS"
fi
}

create_favicons()   # Using real-favicon | npm install cli-real-favicon -g
{
if [ "$FAVICONS" = true ]; then
    if [ -f "favicon.png" ] && [ -f "favicon_cfg.json" ]; then # Make sure we have all our files
        real-favicon generate favicon_cfg.json f_report.json ${SITE_BUILD_DIR}
        rm -f f_report.json
        echo "Generated favicon"
    else
        echo "Missing either favicon.png or favicon_cfg.json in the root directory of this site, can't generate thumbnails"
    fi
fi
}

create_thumbnails()
{
if [ "$THUMBNAILS" = true ] && [ -d "$IMG_SRC_DIR" ] ; then
    rm -rf ${TMP_THUMB_DIR} && mkdir ${TMP_THUMB_DIR}  # Housekeeping
    rm -rf ${TMP_THUMB_DIR2} && mkdir ${TMP_THUMB_DIR2}  # Housekeeping
    find ${IMG_THUMB_DIR} -name '*.DS_Store' -type f -delete # Delete pesky .DS_Store files
    rsync -a --exclude '*thumbnails/*' --exclude '.DS_Store' ${IMG_SRC_DIR} ${TMP_THUMB_DIR}  # Move images to /tmp/
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
    brew install jpegoptim
    brew install optipng
    gem install --user-install bundler jekyll
    npm install babel-cli -g
    npm install babel-preset-env -g
    npm install google-closure-compiler -g
    npm install uglifycss -g
    npm install html-minifier-cli -g
    npm install cli-real-favicon -g
    bundle install
    echo "Dependencies installed."
fi

# Run this script with the "-i" flag to process images (takes longer)
if [ "$ARG_I" = true ]; then
    make_tmp_dirs && create_thumbnails && run_image_tasks
fi

# Minify Source Javascript/CSS
minify_src_js && minify_src_css

# Build with Jekyll
if [ -n "$IS_JEKYLL_SITE" ] && [ "$IS_JEKYLL_SITE" = true ]; then
    bundle exec jekyll build
fi

# Or, move everything to the output directory
if [ -n "$IS_JEKYLL_SITE" ] && [ "$IS_JEKYLL_SITE" = false ]; then
    make_site_output_dir && move_to_output_dir
fi

# Babelify/Minify Build Javascript/CSS
babelify_build_js && minify_build_js && minify_build_css

#Minify build HTML
minify_build_html

# Create favicons
create_favicons

# Upload to S3 - unless -n (no-upload) is passed in
if [ "$ARG_N" = false ]; then
    aws s3 sync --delete --size-only ${SITE_BUILD_DIR} ${SITE_S3} --exclude "*build_log.txt" --exclude "*.idea*" --exclude "*.sh" --exclude "*.git*" --exclude "*.DS_Store"
    
    # Invalidate Cloudfront Cache if requested
    if [ "$ARG_R" = true ]; then
        aws cloudfront create-invalidation --distribution-id ${CF_DIST_ID} --paths ${CF_PATH}
        echo "Invalidated Cloudfront cache."
    fi
    
    echo "Uploaded to S3."
fi

# Write to our build log if we have modified our images
if [ "$ARG_I" = true ] && [ "$ARG_C" = true ]; then
    write_build_log
fi

echo "Done!"