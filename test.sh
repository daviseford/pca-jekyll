#!/usr/bin/env bash
CSS_DIR='./public/css/'
minify_css()
{
find ${CSS_DIR} -name "*.min.css" -type f|xargs rm -f   # Delete existing minified files
# Using Uglify - npm install uglifycss -g
for file in `find ${CSS_DIR} -name "*.css" -type f`; do
    uglifycss --ugly-comments ${file} > "${file/.css/.min.css}" # Create new minified CSS file
done
}

minify_css