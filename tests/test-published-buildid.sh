#!/usr/bin/env bash
# Guards the branch-anchored buildid parser used by scripts/published-buildid.sh.
# A branch name appears in several places in steamcmd app_info output; the parser
# must pick the buildid under depots->branches-><branch>, not a stray earlier mention
# or the wrong branch.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="$HERE/fixtures/app_info.txt"

parse() {
    awk -v branch="\"$1\"" '
        /"branches"/ { inb = 1 }
        inb && index($0, branch) { inbr = 1 }
        inbr && /"buildid"/ { gsub(/[^0-9]/, "", $2); print $2; exit }
    ' "$FIX"
}

check() {
    local branch="$1" want="$2" got
    got="$(parse "$branch")"
    if [ "$got" != "$want" ]; then
        echo "FAIL: branch=$branch got '$got' want '$want'" >&2
        exit 1
    fi
    echo "PASS: branch=$branch -> $got"
}

# public must skip the decoy 11111111 (before the branches block) and unstable/1.4.
check public 19283746
check unstable 55555555
check 1.4 40404040
echo "all parser tests passed"
