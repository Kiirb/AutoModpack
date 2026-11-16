#!/usr/bin/env bash
# Build upstream AutoModpack + trusted-server.patch and publish it as a release
# on the fork. Used by .github/workflows/trusted-update.yml, also runnable locally.
#
# Env:
#   MAJOR     upstream major version to follow (default 4) - only stable vMAJOR.x.y tags
#   TARGETS   space-separated stonecutter targets (default "1.21.1-neoforge")
#   TAG       build this upstream tag instead of the newest stable one
#   FORCE     "true" = rebuild and replace the release for this tag even if it exists
#             (clients that already have this version won't reinstall it)
#   PUBLISH   "false" = build only, don't create a release
#   GH_REPO   fork to publish to (default Kiirb/AutoModpack)
#   WORK      scratch directory (default: mktemp -d)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/trusted-server.patch"
UPSTREAM=https://github.com/Skidamek/AutoModpack.git
MAJOR="${MAJOR:-4}"
TARGETS="${TARGETS:-1.21.1-neoforge}"
GH_REPO="${GH_REPO:-Kiirb/AutoModpack}"
FORCE="${FORCE:-false}"
PUBLISH="${PUBLISH:-true}"
WORK="${WORK:-$(mktemp -d)}"

if [ -z "${TAG:-}" ]; then
    TAG="$(git ls-remote --tags --refs "$UPSTREAM" "v$MAJOR.*" | sed 's|.*refs/tags/||' \
        | grep -E "^v$MAJOR\.[0-9]+\.[0-9]+$" | sort -V | tail -1)"
fi
[ -n "$TAG" ] || { echo "!! No stable upstream v$MAJOR.x.y tag found"; exit 1; }
VERSION="${TAG#v}"
PATCH_SHA="$(sha256sum "$PATCH" | cut -c1-64)"
echo ">> Upstream $TAG, patch ${PATCH_SHA:0:12}, targets: $TARGETS"

# One release per upstream version, like the official AutoModpack
REL="$TAG-trusted"
if [ "$PUBLISH" != "false" ] && gh release view "$REL" -R "$GH_REPO" >/dev/null 2>&1; then
    if [ "$FORCE" != "true" ]; then
        echo ">> Release $REL already exists - nothing to do."
        exit 0
    fi
    echo ">> FORCE: will replace existing release $REL after a successful build"
    REPLACE=1
fi

SRC="$WORK/src"
rm -rf "$SRC"
git clone --quiet --filter=blob:none --branch "$TAG" "$UPSTREAM" "$SRC"
cd "$SRC"
if ! git -c user.name=trusted-build -c user.email=trusted-build@localhost am -3 --quiet "$PATCH"; then
    echo "!! trusted-server.patch does not apply to $TAG - update the patch (see README)."
    exit 1
fi

TASKS=(); for t in $TARGETS; do TASKS+=("$t:build"); done
./gradlew --no-configuration-cache --no-daemon "${TASKS[@]}" -x test

OUT="$WORK/out"; rm -rf "$OUT"; mkdir -p "$OUT"

ENTRIES="[]"
for t in $TARGETS; do
    mc="${t%-*}"; loader="${t##*-}"
    built="$SRC/merged/automodpack-mc$mc-$loader-$VERSION.jar"
    sha1="$(sha1sum "$built" | cut -c1-40)"
    name="automodpack-mc$mc-$loader-$VERSION.jar"
    cp "$built" "$OUT/$name"
    ENTRIES="$(jq -c --arg v "$VERSION" --arg mc "$mc" --arg l "$loader" --arg n "$name" \
        --arg u "https://github.com/$GH_REPO/releases/download/$REL/$name" --arg s "$sha1" \
        --argjson size "$(stat -c %s "$built")" \
        '. + [{version:$v, mcVersion:$mc, loader:$l, fileName:$n, url:$u, sha1:$s, size:$size}]' <<<"$ENTRIES")"
    echo ">> Built $name"
done

jq -n --arg tag "$TAG" --arg p "$PATCH_SHA" --argjson files "$ENTRIES" \
    '{upstreamTag:$tag, patchSha256:$p, files:$files}' > "$OUT/trusted-manifest.json"
cp "$PATCH" "$OUT/trusted-server.patch"
cat "$OUT/trusted-manifest.json"

if [ "$PUBLISH" = "false" ]; then
    echo ">> PUBLISH=false - output in $OUT"
    exit 0
fi

if [ "${REPLACE:-0}" = 1 ]; then
    gh release delete "$REL" -R "$GH_REPO" --yes --cleanup-tag
fi
echo ">> Publishing $REL"
gh release create "$REL" "$OUT"/* -R "$GH_REPO" --latest \
    ${GITHUB_SHA:+--target "$GITHUB_SHA"} \
    --title "AutoModpack $VERSION (trusted-server patch)" \
    --notes "Built automatically from upstream [$TAG](https://github.com/Skidamek/AutoModpack/releases/tag/$TAG) + \`trusted-server.patch\` (sha256 \`${PATCH_SHA:0:12}\`).
Targets: $TARGETS

Patched clients install this on their next launch."
echo ">> Published $REL"
