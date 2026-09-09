#!/bin/bash
# Prints the download history that the Download counts workflow records.
#
#   Scripts/downloads.sh              the daily total and what it moved by
#   Scripts/downloads.sh --by-version the latest day, broken out per release
#
# The numbers come from downloads.csv on the `metrics` branch, which the
# workflow appends to once a day. GitHub itself only ever reports a running
# total, so a day missing from the CSV is a day that is gone: nothing here
# can reconstruct it.
#
# A download is an asset fetch, not a person. Bots and CI are in these
# numbers, and one person trying three versions is three of them. Read it
# as a ceiling and as a shape, never as a user count.

set -euo pipefail

repo=${OCARINA_REPO:-VaibhavVishal07/Ocarina-Terminal}

csv=$(gh api "repos/${repo}/contents/downloads.csv?ref=metrics" --jq .content 2>/dev/null | base64 -d) || {
  echo "No downloads.csv on the metrics branch yet." >&2
  echo "Run: gh workflow run download-counts.yml --repo ${repo}" >&2
  exit 1
}

if [ "${1:-}" = "--by-version" ]; then
  latest=$(echo "$csv" | tail -n +2 | cut -d, -f1 | sort -u | tail -1)
  echo "$latest"
  echo "$csv" | awk -F, -v d="$latest" '$1==d && $4>0 { printf "  %-8s %-40s %s\n", $2, $3, $4 }'
  exit 0
fi

echo "$csv" | tail -n +2 | awk -F, '{ total[$1] += $4 } END { for (d in total) print d, total[d] }' \
  | sort \
  | awk '{ if (NR == 1) printf "%s  %6d\n", $1, $2; else printf "%s  %6d  %+d\n", $1, $2, $2 - prev; prev = $2 }'
