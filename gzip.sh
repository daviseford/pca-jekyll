#!/bin/bash

# THIS FILE IS UNUSED
# JUST HERE AS A CURIOSITY
# DOESN'T SEEM TO WORK LOL

# This file creates gzipped copies of everything that Jekyll generates
# And uploads it to S3 with the proper encoding
# Since we're using S3 as a static host, we need to do this

SITE_DIR='./_site'
GZIP_DIR='./_gzip'

# So copy the site to another folder,
# gzip that folder
# append everything in that folder with .gz
# Upload to S3 with content-encoding set to --content-encoding gzip

# we gzip up all files so that they are smaller
rm -rf ${GZIP_DIR} # Delete _gzip/ folder
rsync -a --progress ${SITE_DIR} ${GZIP_DIR}
gzip -9fr ${GZIP_DIR}

# And then upload to S3 with --content-encoding gzip
# http://www.cheeming.com/2015/03/29/advanced-tricks-hosting-website-on-amazon-s3-enable-gzip-compression.html
aws s3 sync --content-encoding gzip --size-only ${GZIP_DIR} s3://parkcenterautomotive.com/