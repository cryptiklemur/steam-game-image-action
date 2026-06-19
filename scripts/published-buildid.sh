#!/usr/bin/env bash
# Print the published Steam buildid for an app on a given branch.
#
# steamcmd +app_info_print emits a nested VDF where the buildid we want lives at
# depots -> branches -> <branch> -> buildid. The branch name appears in several
# places in the output, so we anchor the parse to the "branches" block first, then
# the requested branch, then its first "buildid". Without that anchoring you get
# the wrong branch's id (e.g. "public" when you wanted a beta).
#
# Requires: steamcmd on PATH, a config.vdf already written (steam-login.sh),
# STEAM_USERNAME set. Env: APP_ID (default 294100), BRANCH (default public).
# Prints the integer buildid to stdout, or nothing on failure.
set -euo pipefail

: "${STEAM_USERNAME:?set STEAM_USERNAME}"
APP_ID="${APP_ID:-294100}"
BRANCH="${BRANCH:-public}"

steamcmd \
    +@ShutdownOnFailedCommand 1 \
    +@NoPromptForPassword 1 \
    +login "$STEAM_USERNAME" \
    +app_info_update 1 \
    +app_info_print "$APP_ID" \
    +quit 2>/dev/null \
  | awk -v branch="\"$BRANCH\"" '
      /"branches"/ { inb = 1 }
      inb && index($0, branch) { inbr = 1 }
      inbr && /"buildid"/ { gsub(/[^0-9]/, "", $2); print $2; exit }
    '
