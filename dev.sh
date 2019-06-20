#!/bin/bash

# Open our default browser to the local blog server address
open http://127.0.0.1:4000/

# Start Jekyll
bundle exec jekyll serve --watch
