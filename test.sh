#!/usr/bin/env bash

minify_html()
{
# Using html-minifier
# npm install html-minifier-cli -g

TMP_EXT='.min'

# Make a minified copy of each .html file
for file in `find ./_site/ -name "*.html" -type f`; do
    htmlmin -o "${file}${TMP_EXT}" ${file}
done

# Now overwrite the older HTML with the new, minified version
for file in `find ./_site/ -name "*${TMP_EXT}" -type f`; do
    FILE_EXT="html${TMP_EXT}"
    mv ${file} "${file/$FILE_EXT/html}"
done

}

minify_html