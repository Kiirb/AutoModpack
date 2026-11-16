#!/usr/bin/env bash
# Local helper for the trusted-server AutoModpack build.
# Normally you don't need this: GitHub Actions checks upstream daily and publishes
# new builds by itself (see README.md).
#
#   ./update.sh local [vX.Y.Z]  rebase ./AutoModpack (branch trusted-server) onto the newest
#                               stable v4 tag (or the given one) and build 1.21.1-neoforge.
#                               Jar ends up in AutoModpack/merged/. Use this to work on the patch.
#   ./update.sh publish         export the patch commit to trusted-server.patch, push it to the
#                               fork's automation branch, and trigger a check for upstream updates.
#                               (One release per AutoModpack version: a changed patch is used from
#                               the next upstream release on. To rebuild the current version anyway:
#                               gh workflow run trusted-update.yml -R Kiirb/AutoModpack -f force=true)
#   ./update.sh status          show the latest GitHub Actions runs
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/AutoModpack"
GH_REPO=Kiirb/AutoModpack
WORKFLOW=trusted-update.yml
TARGET=1.21.1-neoforge
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/mise/installs/java/21.0.2}"

patch_commit() { git -C "$REPO" log -1 --format=%H --grep='^trusted-server:' trusted-server; }

case "${1:-}" in
local)
    cd "$REPO"
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "!! Uncommitted changes in $REPO - commit (--amend) or stash them first."; exit 1
    fi
    git fetch --tags --quiet origin
    TAG="${2:-$(git tag -l 'v4.*' | grep -E '^v4\.[0-9]+\.[0-9]+$' | sort -V | tail -1)}"
    PATCH_COMMIT="$(patch_commit)"
    git switch --quiet trusted-server
    if [ "$(git rev-parse HEAD~1)" != "$(git rev-parse "$TAG^{commit}")" ]; then
        echo ">> Rebasing trusted-server patch onto $TAG"
        git reset --quiet --hard "$TAG"
        if ! git cherry-pick "$PATCH_COMMIT"; then
            echo "!! Conflicts. Fix them in $REPO, then: git add -A && git cherry-pick --continue"; exit 1
        fi
    fi
    echo ">> Building $TARGET from $TAG + patch"
    ./gradlew --no-configuration-cache "$TARGET:build" -x test
    ls -1 "$REPO"/merged/*.jar
    ;;
publish)
    cd "$HERE"
    git -C "$REPO" format-patch -1 --stdout "$(patch_commit)" > trusted-server.patch
    git -C "$REPO" push --quiet --force fork trusted-server
    if [ -n "$(git status --porcelain trusted-server.patch)" ]; then
        git add trusted-server.patch
        git commit --quiet -m "Update trusted-server.patch"
        git push --quiet origin automation   # push also starts the workflow
        echo ">> Patch changed - pushed. GitHub Actions is checking for a version to build."
    else
        gh workflow run "$WORKFLOW" -R "$GH_REPO"
        echo ">> Patch unchanged - triggered a check for new upstream releases."
    fi
    echo "   Follow it with: ./update.sh status"
    ;;
status)
    gh run list -R "$GH_REPO" --workflow "$WORKFLOW" --limit 5
    ;;
*)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
