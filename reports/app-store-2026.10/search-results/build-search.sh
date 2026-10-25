#!/bin/sh
set -eu
cd "$(dirname "$0")"
magick -background '#F6F2EB' search-art.svg \
  -font '/System/Library/Fonts/Supplemental/Arial Bold.ttf' -fill '#202B2D' \
  -pointsize 110 -annotate +1730+300 'Avenkin' \
  -gravity North -pointsize 230 -annotate +0+530 'Talk. Ask.' \
  -annotate +0+810 'Get things done.' \
  -font '/System/Library/Fonts/Supplemental/Arial.ttf' \
  -fill '#68716C' -pointsize 82 -annotate +0+1140 'Your AI. Your terms.' \
  -alpha off -colorspace sRGB -depth 8 -define png:color-type=2 \
  avenkin-search-3840x2560.png
