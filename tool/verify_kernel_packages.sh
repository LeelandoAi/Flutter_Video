#!/bin/sh
set -eu

PACKAGES=". packages/lee_video_erika packages/lee_video_media_kit packages/lee_video_fvp packages/lee_video_video_player packages/lee_video_all"

flutter analyze
flutter test

for package in $PACKAGES; do
  echo "==> dry-run $package"
  (cd "$package" && PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run)
done
