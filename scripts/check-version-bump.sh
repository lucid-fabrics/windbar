#!/bin/sh
# Fail if the project.yml version in this commit is not strictly newer
# than the most recent vX.Y.Z tag on the default branch.
#
# Re-tagging the exact same version+build is rejected by the same-version
# build check; a downgrade is rejected by sort -V's real semver compare.
# The first release on a brand-new repo (no prior tag) always passes.
#
# Usage (CI job uses HEAD):
#   ./scripts/check-version-bump.sh
#
# Local dry-run, from any commit:
#   ./scripts/check-version-bump.sh
#
# Run the test suite (12 cases, includes 1.9.0 -> 1.10.0 regression):
#   ./scripts/test-check-version-bump.sh
#
# Soft spots (intentional, not bugs):
#   - Pre-release and build-metadata suffixes (1.0.0-rc.1, 1.0.0+sha) are
#     not semver-2.0.0. sort -V's handling of them is coreutils-version
#     dependent. Project uses plain X.Y.Z tags.
#   - This script is advisory: a maintainer with force-push or admin
#     access can bypass it. It is not a security boundary.

set -eu

if ! command -v sort >/dev/null 2>&1; then
    echo "::error::sort(1) is required"
    exit 1
fi

if [ ! -f project.yml ]; then
    echo "::error::project.yml not found (run from repo root)"
    exit 1
fi

# Find the most recent tag (by version-sorted refname). If that tag points
# at HEAD, skip it: the user is re-tagging the current commit, so the
# "prior release" is HEAD itself and there's nothing to bump against.
last_tag="$(git tag -l --sort=-version:refname 'v*' | head -n1 || true)"
if [ -n "$last_tag" ] && [ "$(git rev-parse "$last_tag")" = "$(git rev-parse HEAD)" ]; then
    last_tag="$(git tag -l --sort=-version:refname 'v*' | sed -n '2p')"
fi

# The bump gate has three cases:
#   - workflow_dispatch (manual upload rebuild) and create (release tag
#     push): bypass entirely. The version on the matching tag is already
#     authoritative.
#   - pull_request: bypass if the PR diff does NOT touch project.yml.
#     Infra-only PRs must not require a version bump.
#   - push (direct to main): enforce - the user must have a real bump.
#   - any other event: enforce conservatively.
#
# Read GITHUB_EVENT_NAME safely - set -u treats unbound differently from empty.
GITHUB_EVENT_NAME="${GITHUB_EVENT_NAME-}"
case "$GITHUB_EVENT_NAME" in
    workflow_dispatch|create)
        read_field() {
            grep "^    $1:" "$2" | sed -E "s/^    $1: *\"([^\"]*)\".*/\\1/"
        }
        cur_ver="$(read_field MARKETING_VERSION project.yml)"
        cur_build="$(read_field CURRENT_PROJECT_VERSION project.yml)"
        last_tag_for_log="${last_tag:-<none>}"
        echo "GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME}: skipping version-bump check for ${cur_ver}+${cur_build} (tag ${last_tag_for_log})."
        exit 0
        ;;
    pull_request)
        # Infra-only PRs (workflow, scripts, docs) must merge without a
        # version bump. The check below only fires if project.yml changed.
        if ! git diff --name-only HEAD~1..HEAD 2>/dev/null | grep -q "^project\.yml$"; then
            echo "pull_request does not touch project.yml: skipping version-bump check."
            exit 0
        fi
        ;;
esac

if [ -z "$last_tag" ]; then
    echo "No prior release tag, accepting initial release."
    exit 0
fi

read_field() {
    grep "^    $1:" "$2" | sed -E "s/^    $1: *\"([^\"]*)\".*/\\1/"
}

cur_ver="$(read_field MARKETING_VERSION project.yml)"
cur_build="$(read_field CURRENT_PROJECT_VERSION project.yml)"
last_ver="${last_tag#v}"
last_build="$(git show "${last_tag}:project.yml" | sed -n 's/^    CURRENT_PROJECT_VERSION: *"\(.*\)".*/\1/p')"

# Re-tagging the same version+build: build number must be strictly greater.
if [ "$cur_ver" = "$last_ver" ] && [ "$cur_build" -le "$last_build" ]; then
    echo "::error::${last_tag} is already at ${cur_ver}+${cur_build}. Bump MARKETING_VERSION or CURRENT_PROJECT_VERSION in project.yml."
    exit 1
fi

# Different version: must be a strictly higher semver, not a downgrade.
# sort -V does real semver compare: 1.10.0 > 1.9.0, not a lexical trap.
if ! printf '%s\n%s\n' "$last_ver" "$cur_ver" | sort -V -c; then
    echo "::error::MARKETING_VERSION $cur_ver is not greater than released $last_tag. Bump it in project.yml."
    exit 1
fi

echo "Bump ok: ${last_tag} -> ${cur_ver}+${cur_build}."
