#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd -P)
PACKAGES=". packages/lee_video_erika packages/lee_video_media_kit packages/lee_video_fvp packages/lee_video_video_player packages/lee_video_all"

cd "$ROOT"
flutter analyze
flutter test

for package in $PACKAGES; do
  echo "==> dry-run $package"
  if [ "$package" = "." ]; then
    (cd "$package" && PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run)
  else
    # Isolate the parent's .pubignore without skipping any Pub validation.
    (
      cd "$package"
      GIT_CEILING_DIRECTORIES="$ROOT/packages" \
        PUB_HOSTED_URL=https://pub.dev \
        dart pub publish --dry-run
    )
  fi
done
