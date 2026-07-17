#!/usr/bin/env bash
set -euo pipefail

event_name="${1:?usage: select-build-targets.sh EVENT BASE_SHA HEAD_SHA}"
base_sha="${2:-}"
head_sha="${3:-}"

all_targets=(
  apogee
  matchexec
  tonysofwestreading
  slamanna-com
  slamanna-food
)

declare -A selected=()

add_targets() {
  local target
  for target in "$@"; do
    selected["$target"]=1
  done
}

add_all_targets() {
  add_targets "${all_targets[@]}"
}

select_stage() {
  case "$1" in
    node-toolchain|node-runner)
      add_targets apogee matchexec tonysofwestreading slamanna-food
      ;;
    go-toolchain|hugo-toolchain|slamanna-com)
      add_targets slamanna-com
      ;;
    rust-toolchain|apogee)
      add_targets apogee
      ;;
    runner-base)
      add_all_targets
      ;;
    matchexec|tonysofwestreading|slamanna-food)
      add_targets "$1"
      ;;
    *)
      # Changes outside a known stage, or to a newly added stage, are treated
      # as shared until the dependency map above is updated.
      add_all_targets
      ;;
  esac
}

stage_at_line() {
  local dockerfile="$1"
  local line_number="$2"

  awk -v target_line="$line_number" '
    NR > target_line { exit }
    toupper($1) == "FROM" {
      stage = ""
      for (field = 2; field <= NF; field++) {
        if (toupper($field) == "AS" && field < NF) {
          stage = $(field + 1)
          break
        }
      }
    }
    END { print stage }
  ' "$dockerfile"
}

select_dockerfile_changes() {
  local temp_dir old_dockerfile new_dockerfile diff_line
  local old_start old_count new_start new_count offset stage

  temp_dir="$(mktemp -d)"
  old_dockerfile="$temp_dir/Dockerfile.old"
  new_dockerfile="$temp_dir/Dockerfile.new"

  if ! git show "${base_sha}:Dockerfile" >"$old_dockerfile" \
    || ! git show "${head_sha}:Dockerfile" >"$new_dockerfile"; then
    rm -rf "$temp_dir"
    add_all_targets
    return
  fi

  while IFS= read -r diff_line; do
    if [[ "$diff_line" =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
      old_start="${BASH_REMATCH[1]}"
      old_count="${BASH_REMATCH[3]:-1}"
      new_start="${BASH_REMATCH[4]}"
      new_count="${BASH_REMATCH[6]:-1}"

      for ((offset = 0; offset < old_count; offset++)); do
        stage="$(stage_at_line "$old_dockerfile" "$((old_start + offset))")"
        select_stage "$stage"
      done

      for ((offset = 0; offset < new_count; offset++)); do
        stage="$(stage_at_line "$new_dockerfile" "$((new_start + offset))")"
        select_stage "$stage"
      done
    fi
  done < <(git diff --unified=0 "$base_sha" "$head_sha" -- Dockerfile)

  rm -rf "$temp_dir"
}

print_targets() {
  local target separator=""

  printf '['
  for target in "${all_targets[@]}"; do
    if [[ -n "${selected[$target]:-}" ]]; then
      printf '%s"%s"' "$separator" "$target"
      separator=','
    fi
  done
  printf ']\n'
}

if [[ "$event_name" == "schedule" || "$event_name" == "workflow_dispatch" ]]; then
  add_all_targets
  print_targets
  exit 0
fi

if [[ -z "$base_sha" || -z "$head_sha" || "$base_sha" =~ ^0+$ ]] \
  || ! git cat-file -e "${base_sha}^{commit}" 2>/dev/null \
  || ! git cat-file -e "${head_sha}^{commit}" 2>/dev/null; then
  add_all_targets
  print_targets
  exit 0
fi

while IFS= read -r changed_file; do
  case "$changed_file" in
    Dockerfile)
      select_dockerfile_changes
      ;;
    hugo/*)
      add_targets slamanna-com
      ;;
    package.json|package-lock.json)
      add_targets tonysofwestreading
      ;;
    scripts/smoke-test.sh|scripts/select-build-targets.sh|.dockerignore|.github/workflows/build.yml)
      add_all_targets
      ;;
    README.md|LICENSE|.gitignore|.github/dependabot.yml|scripts/check-runner-freshness.sh)
      ;;
    *)
      # Unknown build-context files are conservatively treated as shared.
      add_all_targets
      ;;
  esac
done < <(git diff --name-only "$base_sha" "$head_sha")

print_targets
