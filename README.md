# steam-game-image-action

A GitHub Action that downloads a Steam game with `steamcmd` and pushes it as a
**private** OCI image to a registry **you** control — so CI can build mods against
the real game assemblies and launch the game in a container. Defaults to
**RimWorld** (app `294100`) but works for any Steam app you own.

> **The game image is never published by this tool.** You build it from your own
> Steam-owned copy and push it to your own private registry. Only this tooling is
> open source (MIT). Redistributing the publisher's game binaries is not permitted;
> keeping the resulting image private is your responsibility.

## Why

RimWorld mods compile fine against the public [`Krafs.Rimworld.Ref`](https://github.com/Krafs/Rimworld.Ref)
NuGet with no game install. This action covers what that can't:

- **Build against the real shipped assemblies** (`/game/RimWorldLinux_Data/Managed/*.dll`), not ref-only stubs.
- **Run the game in CI** — the default image carries `xvfb` + the X11/GL/audio native
  libs so the Linux build can be launched (bring your own test-runner mod; see caveat).

## Quick start

1. **Prime a steamcmd session once** (locally), on an account that owns the game:

   ```sh
   steamcmd +login your-steam-account     # complete Steam Guard
   base64 -w0 ~/Steam/config/config.vdf   # copy this
   ```

   Save the base64 as a repo secret named `STEAM_CONFIG_VDF`. (The session can
   expire; re-run this and update the secret when it does.)

2. **Add a workflow** (see [`examples/`](examples/)). On-demand:

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

   This pushes `ghcr.io/you/rimworld-game:<version>` + `:latest` (private), labeled
   with `steam.buildid`.

3. **Keep it fresh** — copy [`examples/watch-and-build.yml`](examples/watch-and-build.yml).
   A scheduled run is the watcher: the **build-id gate** compares the published
   buildid to your image's `steam.buildid` label and downloads nothing when they
   match, so cron runs are cheap and only a real new build triggers a rebuild.

## Inputs

| input | default | notes |
|---|---|---|
| `steam-username` | — | account that owns the game |
| `steam-config-vdf` | — | base64 of a steamcmd `config.vdf` (a secret) |
| `app-id` | `294100` | Steam app id (RimWorld) |
| `branch` | `public` | Steam branch, e.g. `1.5`, `1.4` |
| `branch-password` | `""` | for password-protected betas |
| `image` | — | target ref without tag, e.g. `ghcr.io/you/rimworld-game` |
| `registry` / `registry-username` / `registry-password` | `ghcr.io` / actor / — | push auth (GHCR + `GITHUB_TOKEN` works) |
| `runnable` | `true` | `true` = append onto the xvfb/native-deps base; `false` = minimal build/reference base |
| `skip-if-unchanged` | `true` | gate on the `steam.buildid` label |

Outputs: `image-ref`, `version`, `buildid`, `skipped`.

## Using the image

**Build against it** (real assemblies) — a mod project in a container `FROM` the image:

```dockerfile
FROM ghcr.io/you/rimworld-game:latest
# reference /game/RimWorldLinux_Data/Managed/*.dll in your .csproj HintPaths
```

**Launch it** — the runnable base ships a `run-headless` helper (`xvfb-run -a "$@"`):

```sh
docker run --rm ghcr.io/you/rimworld-game:latest run-headless /game/RimWorldLinux
```

> **Headless caveat.** RimWorld has no official headless test mode. This image gives
> you a virtual display and the native deps so a launch can proceed, but you must
> supply a test-runner mod that boots a scenario, asserts, and exits with a status.
> The exact working invocation is game/mod-specific — validate it for your setup.

## How it works

`steamcmd` downloads the game, then `crane append` layers it onto a public,
game-free [`runtime-base`](Dockerfile.runtime-base) image (no Docker daemon needed)
and pushes to your registry, stamping a `steam.buildid` OCI label. The label is the
only state the build-id gate needs.

Two layers of caching keep it cheap:

- **Build-id gate** (`skip-if-unchanged`): when the published buildid already matches
  the image's `steam.buildid` label, the action downloads nothing and pushes nothing.
  No new version → no rebuild.
- **Install cache** (`actions/cache`): on an actual rebuild, the prior game install is
  restored and `app_update` fetches only the changed files (a delta), not the whole
  game. Keyed by app id + branch.

Mechanics are a generalization of a private setup the author runs for another Steam game.

## License

MIT — see [LICENSE](LICENSE). Applies to this tooling only, not to any game content.
