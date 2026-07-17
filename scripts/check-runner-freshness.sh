#!/usr/bin/env bash
set -euo pipefail

dockerfile="${1:-Dockerfile}"
pinned="$(sed -nE 's/^FROM ghcr\.io\/actions\/actions-runner:([^@ ]+).*/\1/p' "$dockerfile" | head -n1)"
releases_json="$(
  curl -fsSL \
    --retry 5 \
    --retry-delay 2 \
    --retry-all-errors \
    --connect-timeout 10 \
    --max-time 60 \
    'https://api.github.com/repos/actions/runner/releases?per_page=100'
)"
latest="$(jq -r '[.[] | select(.draft == false and .prerelease == false)][0].tag_name | sub("^v"; "")' <<<"$releases_json")"

if [[ "$pinned" == "$latest" ]]; then
  echo "Runner image is current at ${pinned}."
  exit 0
fi

first_newer_published="$(
  jq -r --arg pinned "v${pinned}" '
    [.[] | select(.draft == false and .prerelease == false)] as $releases
    | ($releases | map(.tag_name) | index($pinned)) as $pinned_index
    | if $pinned_index == null then
        $releases[-1].published_at
      else
        $releases[$pinned_index - 1].published_at
      end
  ' <<<"$releases_json"
)"
published_epoch="$(date -d "$first_newer_published" +%s)"
now_epoch="$(date +%s)"
age_days="$(( (now_epoch - published_epoch) / 86400 ))"

echo "Pinned runner ${pinned}; latest runner ${latest}; the first newer release is ${age_days} days old."
if (( age_days >= 21 )); then
  echo "::error::The runner base is at least 21 days behind. Merge the pending Dependabot update before GitHub's 30-day deadline."
  exit 1
fi
