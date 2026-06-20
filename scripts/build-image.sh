#!/usr/bin/env bash
# Layer an installed Steam game onto a base image and push it to a registry,
# tagged by version + latest and stamped with the steam.buildid OCI label.
#
# Uses crane, so no Docker daemon is needed (GitHub-hosted runners have one, but
# crane is faster and works the same on any runner).
#
# Env:
#   GAME_DIR          installed game dir (required)
#   IMAGE             target image, e.g. ghcr.io/you/rimworld-game (required)
#   BASE_IMAGE        base to append the game layer onto (required)
#   REGISTRY          registry host for auth (required)
#   REGISTRY_USER     registry username (required)
#   REGISTRY_PASSWORD registry token/password, read from stdin via env (required)
#   STEAM_BUILDID     buildid to stamp as the steam.buildid label (optional)
#   GAME_PATH         path the game lands at inside the image (default /game)
#   PLATFORM          image platform (default linux/amd64)
set -euo pipefail

: "${GAME_DIR:?set GAME_DIR (the installed game)}"
: "${IMAGE:?set IMAGE (target image ref without tag)}"
: "${BASE_IMAGE:?set BASE_IMAGE}"
: "${REGISTRY:?set REGISTRY}"
: "${REGISTRY_USER:?set REGISTRY_USER}"
: "${REGISTRY_PASSWORD:?set REGISTRY_PASSWORD}"
STEAM_BUILDID="${STEAM_BUILDID:-}"
GAME_PATH="${GAME_PATH:-/game}"
PLATFORM="${PLATFORM:-linux/amd64}"

# OCI references must be lowercase (registry owner/repo can be mixed-case).
IMAGE="$(printf '%s' "$IMAGE" | tr '[:upper:]' '[:lower:]')"

if [ ! -d "$GAME_DIR" ] || [ -z "$(find "$GAME_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "GAME_DIR '$GAME_DIR' is missing or empty - did the download run?" >&2
    exit 1
fi

VERSION_RAW="$(cat "$GAME_DIR/Version.txt" 2>/dev/null || true)"
VERSION="$(printf '%s' "$VERSION_RAW" | awk '{print $1}' | tr -c 'A-Za-z0-9._-' '-' | sed 's/-*$//')"
[ -n "$VERSION" ] || VERSION="${STEAM_BUILDID:-unknown}"
echo "steam-game-image: version='$VERSION' buildid='${STEAM_BUILDID:-none}'"

LAYER="$(mktemp -d)/game.tar"
tar -C "$GAME_DIR" \
    --exclude=./steamapps \
    --exclude=./lost+found \
    --transform="s,^\.,${GAME_PATH#/}," \
    -cf "$LAYER" .
echo "steam-game-image: staged layer $(du -h "$LAYER" | cut -f1) at $GAME_PATH"

printf '%s' "$REGISTRY_PASSWORD" | crane auth login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin

crane append --platform "$PLATFORM" -b "$BASE_IMAGE" -f "$LAYER" -t "$IMAGE:$VERSION"
crane tag "$IMAGE:$VERSION" latest

if [ -n "$STEAM_BUILDID" ]; then
    crane mutate "$IMAGE:$VERSION" --label "steam.buildid=$STEAM_BUILDID" -t "$IMAGE:$VERSION"
    crane mutate "$IMAGE:latest"   --label "steam.buildid=$STEAM_BUILDID" -t "$IMAGE:latest"
    echo "steam-game-image: stamped steam.buildid=$STEAM_BUILDID"
else
    echo "steam-game-image: STEAM_BUILDID unset; skipping label stamp" >&2
fi

echo "pushed $IMAGE:$VERSION (+ latest)"

# Outputs for GitHub Actions, if running in one.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "image-ref=$IMAGE:$VERSION"
        echo "version=$VERSION"
        echo "buildid=$STEAM_BUILDID"
    } >> "$GITHUB_OUTPUT"
fi
