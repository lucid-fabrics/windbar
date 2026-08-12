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

# --no-contains HEAD: re-tagging the same commit's own version must not
# flag itself.
last_tag="$(git tag --sort=-version:refname --no-contains HEAD 'v*' | head -n1 || true)"

if [ -z "$last_tag" ]; then
    echo "No prior release tag, accepting initial release."
    exit 0
fi

read_field() {
    sed -n "s/^    $1: *\"\\(.*\\)\".*/\\1/p" "$2"
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
