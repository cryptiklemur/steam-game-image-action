#!/usr/bin/env bash
# Provision a non-interactive steamcmd session from a base64-encoded config.vdf.
#
# CRITICAL ORDERING: steamcmd self-updates on its first run and rewrites its own
# config dir. If credentials are placed first, that self-update clobbers them and
# login fails silently. So we bootstrap (`steamcmd +quit`) BEFORE writing config.vdf.
#
# Requires: steamcmd on PATH, STEAM_CONFIG_VDF_B64 set (base64 of a logged-in
# steamcmd config.vdf). Writes $HOME/Steam/config/config.vdf (chmod 600).
set -euo pipefail

: "${STEAM_CONFIG_VDF_B64:?set STEAM_CONFIG_VDF_B64 (base64 of a steamcmd config.vdf)}"

steamcmd +quit || true

mkdir -p "$HOME/Steam/config"
printf '%s' "$STEAM_CONFIG_VDF_B64" | base64 -d > "$HOME/Steam/config/config.vdf"
chmod 600 "$HOME/Steam/config/config.vdf"
