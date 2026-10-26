#!/bin/sh
set -eu
cd "$(dirname "$0")"
magick -background '#F6F2EB' header-art.svg \
  -font '/System/Library/Fonts/Supplemental/Arial Bold.ttf' -fill '#202B2D' \
  -pointsize 110 -annotate +640+510 'Avenkin' \
  -pointsize 190 -annotate +470+758 'Talk. Ask.' \
  -annotate +470+980 'Get things done.' \
  -font '/System/Library/Fonts/Supplemental/Arial.ttf' \
  -fill '#68716C' -pointsize 76 -annotate +477+1158 'Your AI. Your terms.' \
  -alpha off -colorspace sRGB -depth 8 -define png:color-type=2 \
  avenkin-header-3840x1646.png
