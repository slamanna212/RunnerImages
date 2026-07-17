#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: smoke-test.sh IMAGE TARGET}"
target="${2:?usage: smoke-test.sh IMAGE TARGET}"

common='test "$(id -u)" = 1001; test -x /home/runner/run.sh; ! command -v dockerd; ! command -v containerd; test "$RUNNER_TOOL_CACHE" = /home/runner/_tool; toolcache_probe="$RUNNER_TOOL_CACHE/.runnerimages-write-test"; mkdir "$toolcache_probe"; rmdir "$toolcache_probe"; git --version; gh --version; curl --version; jq --version'
node_toolcache='node_cache=$(find "$RUNNER_TOOL_CACHE/node" -mindepth 2 -maxdepth 2 -name x64 -print -quit); test -n "$node_cache"; test -x "$node_cache/bin/node"; test -f "${node_cache}.complete"'

case "$target" in
  apogee)
    checks="$common; $node_toolcache; node --version; npm --version; rustc --version; cargo --version; pkg-config --exists webkit2gtk-4.1; dpkg-query -W patchelf rpm zsync"
    ;;
  matchexec)
    checks="$common; $node_toolcache; node --version; npm --version; docker --version; docker buildx version"
    ;;
  tonysofwestreading)
    checks="$common; $node_toolcache; node --version; npm --version; browser=\$(find /home/runner/.cache/ms-playwright -type f \( -name chrome -o -name headless_shell \) -print -quit); test -n \"\$browser\"; \"\$browser\" --version"
    ;;
  slamanna-com)
    checks="$common; go_cache=\$(find \"\$RUNNER_TOOL_CACHE/go\" -mindepth 2 -maxdepth 2 -name x64 -print -quit); test -n \"\$go_cache\"; test -x \"\$go_cache/bin/go\"; test -f \"\${go_cache}.complete\"; go version; hugo version; tidy -version"
    ;;
  slamanna-food)
    checks="$common; $node_toolcache; node --version; npm --version"
    ;;
  *)
    echo "unknown target: $target" >&2
    exit 2
    ;;
esac

docker run --rm --entrypoint bash "$image" -lc "$checks"
