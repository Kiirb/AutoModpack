# AutoModpack "trusted-server" build

Patched AutoModpack for the Entenschrank server (1.21.1 NeoForge).
This is the `automation` branch of https://github.com/Kiirb/AutoModpack.

## What the patch does
- No "MODPACK UPDATE / unverified JARs" warning (and no 10 s timer) when the
  modpack contains self-compiled mods that aren't on Modrinth/CurseForge.
- On clients, the self-updater never downloads the official Modrinth jar.
  On every launch it reads
  `https://github.com/Kiirb/AutoModpack/releases/latest/download/trusted-manifest.json`
  and installs the patched jar listed there if its SHA1 differs from the running jar
  (regardless of `selfUpdater` / `syncAutoModpackVersion` in the client config).
- Server behaviour is unchanged.

The whole patch is `trusted-server.patch` (one commit). Patched files, all under
`loader/core/src/main/java/pl/skidam/automodpack_loader_core/`:
- `client/ModpackUpdater.java` - `hasUnverifiedJars()` always returns false
- `SelfUpdater.java` - clients hand off to `TrustedUpdater`
- `TrustedUpdater.java` - new; manifest-based updater

## Automatic updates (GitHub Actions)
`.github/workflows/trusted-update.yml` runs daily and:
1. finds the newest stable upstream `v4.x.y` tag of Skidamek/AutoModpack,
2. skips if the latest release already is that tag + the current patch,
3. otherwise clones upstream, applies `trusted-server.patch`, builds `1.21.1-neoforge`,
4. publishes release `vX.Y.Z-trusted.N` with the jar, `trusted-manifest.json` and the patch.

Patched clients pick it up on their next launch. It also runs when the patch is pushed,
and can be started by hand (Actions tab, or `./update.sh publish`).
If the patch stops applying to a new upstream release, the run fails and GitHub emails you;
clients just stay on the last good build.

Only v4 is followed on purpose: 5.x may not talk to a 4.x server. To move to v5, update the
patch for it, change `MAJOR` in the workflow, and update the server jar at the same time.

**The server jar is NOT updated automatically** - the server never sends its own AutoModpack
jar. After a new release, put the jar on the server by hand and restart.

## Working on the patch locally
`AutoModpack/` (not in this repo) is a clone of upstream; branch `trusted-server` = upstream tag + the patch commit.

    ./update.sh local          # rebase onto newest stable v4 tag and build (jar in AutoModpack/merged/)
    # edit files in AutoModpack/, then: git -C AutoModpack commit -a --amend
    ./update.sh publish        # export + push the patch -> Actions builds and releases it
    ./update.sh status         # recent Actions runs

To recreate `AutoModpack/` on a new machine:

    git clone https://github.com/Skidamek/AutoModpack.git AutoModpack
    cd AutoModpack && git remote add fork https://github.com/Kiirb/AutoModpack.git
    git fetch fork trusted-server && git switch -c trusted-server fork/trusted-server

## First install for a friend (one time only)
Delete `automodpack-*.jar` from the instance's `mods` folder and drop in the
`automodpack-...-trusted-xxxxxxxx.jar` from the latest release on the fork.
The official AutoModpack can't switch to this build by itself.
