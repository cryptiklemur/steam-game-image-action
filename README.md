# steam-game-image-action

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/quality_gate?project=cryptiklemur_steam-game-image-action)](https://sonarcloud.io/summary/new_code?id=cryptiklemur_steam-game-image-action)
[![Code Smells](https://sonarcloud.io/api/project_badges/measure?project=cryptiklemur_steam-game-image-action&metric=code_smells)](https://sonarcloud.io/summary/new_code?id=cryptiklemur_steam-game-image-action)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=cryptiklemur_steam-game-image-action&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=cryptiklemur_steam-game-image-action)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=cryptiklemur_steam-game-image-action&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=cryptiklemur_steam-game-image-action)

Downloads a Steam game with `steamcmd` and pushes it as a private OCI image to a
registry you control, so CI can build mods against the real game assemblies and
launch the game in a container. Defaults to RimWorld (app `294100`) but works for
any Steam app you own.

The game image is never published by this tool. You build it from your own
Steam-owned copy and push it to your own private registry. Only the tooling here is
open source (MIT). Redistributing the publisher's game binaries isn't allowed, and
keeping the resulting image private is on you.

## Why bother

For a lot of games a community reference package lets mods compile with no game install at
all, so why bother with this? Two reasons a stub package can't cover:

- It builds against the real shipped assemblies instead of ref-only stubs, so what compiles
  in CI is what actually loads in the game.
- It can run the game in CI. The default image carries `xvfb` and the X11/GL/audio native
  libs so a Linux build can launch. You supply the test-runner mod (see the caveat below).

## Quick start

First, prime a steamcmd session once, locally, on an account that owns the game:

```sh
steamcmd +login your-steam-account     # complete Steam Guard
base64 -w0 ~/Steam/config/config.vdf   # copy this
```

Save the base64 blob as a repo secret named `STEAM_CONFIG_VDF`. The session can
expire, so when it does, re-run this and update the secret.

Then add a workflow (there are more in [`examples/`](examples/)). On-demand looks like:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions: { packages: write, contents: read }
    steps:
      - uses: cryptiklemur/steam-game-image-action@v1
        with:
          steam-username: your-steam-account
          steam-config-vdf: ${{ secrets.STEAM_CONFIG_VDF }}
          image: ghcr.io/${{ github.repository_owner }}/rimworld-game
          registry-password: ${{ secrets.GITHUB_TOKEN }}
```

That pushes `ghcr.io/you/rimworld-game:<version>` and `:latest` (both private),
labeled with `steam.buildid`.

To keep it fresh, copy [`examples/watch-and-build.yml`](examples/watch-and-build.yml).
A scheduled run acts as the watcher: the build-id gate compares the published buildid
against your image's `steam.buildid` label and downloads nothing when they match. So
cron runs stay cheap and only a genuinely new build kicks off a rebuild.

## Inputs

| input | default | notes |
|---|---|---|
| `steam-username` | N/A | account that owns the game |
| `steam-config-vdf` | N/A | base64 of a steamcmd `config.vdf` (a secret) |
| `app-id` | `294100` | Steam app id (RimWorld) |
| `branch` | `public` | Steam branch, e.g. `1.5`, `1.4` |
| `branch-password` | `""` | for password-protected betas |
| `image` | N/A | target ref without tag, e.g. `ghcr.io/you/rimworld-game` |
| `registry` / `registry-username` / `registry-password` | `ghcr.io` / actor / N/A | push auth (GHCR + `GITHUB_TOKEN` works) |
| `runnable` | `true` | `true` appends onto the xvfb/native-deps base; `false` gives a minimal build/reference base |
| `include-paths` | `""` (whole game) | space/newline-separated subpaths to include, e.g. `RimWorldLinux_Data/Managed` for a DLLs-only image |
| `skip-if-unchanged` | `true` | gate on the `steam.buildid` label |

How people usually run it:

- **Runnable (default):** `runnable: true` with `include-paths` empty gives you the whole
  game on the xvfb base, so you can launch it in CI. It's big, on the order of a GB.
- **Build/reference only:** `include-paths: RimWorldLinux_Data/Managed` with `runnable: false`
  gets you just the managed assemblies on a minimal base. Tiny, and enough to compile against
  the real DLLs without dragging the whole game along. (`include-paths` is relative to the game
  install, and the `*_Data/Managed` layout is a Unity thing.)

Outputs: `image-ref`, `version`, `buildid`, `skipped`.

## Using the image

The image has the real shipped assemblies in it, so your mod's CI can build straight against
them. Pull the image, copy the managed DLLs onto the runner, build. A whole mod workflow:

```yaml
# .github/workflows/build.yml in your mod repo
jobs:
  build:
    runs-on: ubuntu-latest
    permissions: { packages: read, contents: read }
    steps:
      - uses: actions/checkout@v4

      - name: Stage real game assemblies from the image
        env:
          GAME_IMAGE: ghcr.io/${{ github.repository_owner }}/rimworld-game:latest
        run: |
          set -euo pipefail
          echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin
          docker pull -q "$GAME_IMAGE"
          cid="$(docker create "$GAME_IMAGE")"
          sudo mkdir -p /mnt/games/RimWorld
          sudo chown "$(id -u):$(id -g)" /mnt/games/RimWorld
          docker cp "$cid:/game/RimWorldLinux_Data" /mnt/games/RimWorld/RimWorldLinux_Data
          docker rm -f "$cid" >/dev/null
          test -f /mnt/games/RimWorld/RimWorldLinux_Data/Managed/Assembly-CSharp.dll

      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: 9.0.x }

      # Point your .csproj at the staged DLLs (a Reference/HintPath guarded by Exists()),
      # then build.
      - run: dotnet build YourMod.sln -c Release
```

The full runnable copy is in [`examples/build-mod-against-game.yml`](examples/build-mod-against-game.yml).

To launch it, the runnable base ships a `run-headless` helper (`xvfb-run -a "$@"`):

```sh
docker run --rm ghcr.io/you/rimworld-game:latest run-headless /game/RimWorldLinux
```

One thing to know about headless runs: RimWorld has no official headless test mode.
This image gives you a virtual display and the native deps so a launch can proceed,
but you still have to supply a test-runner mod that boots a scenario, asserts, and
exits with a status. The exact working invocation is game and mod specific, so
validate it for your own setup.

## How it works

`steamcmd` downloads the game, then `crane append` layers it onto a public,
game-free [`runtime-base`](Dockerfile.runtime-base) image (no Docker daemon needed)
and pushes to your registry, stamping a `steam.buildid` OCI label. That label is the
only state the build-id gate needs.

Caching keeps it cheap, in two places:

- Build-id gate (`skip-if-unchanged`): when the published buildid already matches the
  image's `steam.buildid` label, the action downloads nothing and pushes nothing. No
  new version, no rebuild.
- Install cache (`actions/cache`): on an actual rebuild, the prior game install gets
  restored and `app_update` fetches only the changed files (a delta) instead of the
  whole game. Keyed by app id and branch.

It's basically a cleaned-up version of a private setup I run for another Steam game.

## License

MIT, see [LICENSE](LICENSE). Applies to this tooling only, not to any game content.
