# RunnerImages

Purpose-built GitHub Actions Runner Controller images for the projects hosted on
the `rapture-*` runner scale sets in the homelab Kubernetes cluster.

The Kubernetes nodes run Debian 13, while these containers intentionally extend
GitHub's supported Ubuntu 24.04 ARC image. Containers share the host kernel, not
the host userspace, so native dependencies are installed for Ubuntu Noble.

## Images

| Package | Included workload tooling |
| --- | --- |
| `ghcr.io/slamanna212/runnerimages/apogee` | Node 24, Rust, GitHub CLI, Tauri Linux dependencies |
| `ghcr.io/slamanna212/runnerimages/matchexec` | Node 24, Docker CLI and Buildx |
| `ghcr.io/slamanna212/runnerimages/tonysofwestreading` | Node 24, Playwright Chromium and browser libraries |
| `ghcr.io/slamanna212/runnerimages/slamanna-com` | Go, Hugo Extended and HTML Tidy |
| `ghcr.io/slamanna212/runnerimages/slamanna-food` | Node 24 and common runner utilities |

All images retain GitHub's `/home/runner/run.sh` entrypoint contract and run jobs
as the upstream `runner` user (UID 1001). They contain no application source,
dependency trees, credentials, or secrets. Every image includes the GitHub CLI
along with the common runner utilities.

## Development

Build and test one target locally:

```bash
docker build --target apogee -t local/runner-apogee:test .
./scripts/smoke-test.sh local/runner-apogee:test apogee
```

Pull requests build and scan every target. Merges to `main`, the weekly schedule,
and manual dispatches publish `latest` and immutable workflow-run tags with SBOM
and provenance attestations. Dependabot maintains container stages, workflow
actions, the Hugo build dependency, and the Playwright tool pin. Renovate in
`HomelabArgoCD` pins `latest` to a digest and groups new image digests into a
reviewable rollout PR.

The packages must be public so ARC can pull them anonymously. GitHub may create a
new GHCR package as private on first publication; if so, set its visibility to
public once in the package settings.
