# Upgrade ArtPlayer to 5.x and enable external subtitles in ReCasaOS

This guide documents a working upgrade of the ReCasaOS web player from ArtPlayer 4.6.2 to ArtPlayer 5.4.0, including a subtitle selector for external subtitle files next to a video. It also covers a Vue compatibility error encountered during the upgrade.

> **Scope:** ReCasaOS/CasaOS frontend bundles are built assets. Their names, module IDs, and component code can change between releases. This is a manual patch for the specific frontend version you inspect. Do not copy the chunk names or module IDs from another installation without checking them first. A ReCasaOS update may overwrite these changes.

## What the change does

- Replaces the ArtPlayer implementation used by the video player with ArtPlayer 5.x.
- Adds an ArtPlayer settings entry that lists matching `.srt` files and switches the active subtitle.
- Handles a legacy Vue-APlayer module that expects a default Vue export, while the ReCasaOS frontend uses Vue 3 named exports. Without that compatibility guard, the browser console can report `Cannot read properties of undefined (reading 'version')` before the player initializes.
- Uses new content-hashed bundle filenames and updates the webpack runtime and HTML entry point so browsers request the patched files.

## Before you start

1. Confirm that the target is ReCasaOS and note its version. This guide was verified on a ReCasaOS setup whose bundled ArtPlayer reported 4.6.2.
2. Ensure you have SSH access and `sudo` rights. Run commands on the server, not in the CasaOS browser terminal.
3. Identify the actual frontend document root and the JavaScript bundles it serves. Do not assume CasaOS and ReCasaOS use the same path. Browser DevTools **Network** is useful: load the dashboard, open the JavaScript request URL, and locate the deployed files on disk.
4. Make a timestamped copy of the current `index.html`, webpack runtime, video component chunk, and ArtPlayer chunk. Keep the backup outside the directory that an update may replace.
5. Download the official ArtPlayer package for the intended version and inspect its license and package contents before using it. This example used ArtPlayer 5.4.0; check the [ArtPlayer npm package](https://www.npmjs.com/package/artplayer) for the current release.

Example SSH connection:

```sh
ssh <admin-user>@<server-address>
sudo -i
```

Never put a password in this guide or in shell command history.

## Find the active bundles

Use the browser's Network panel (disable cache while DevTools is open) to find the exact files requested by the ReCasaOS page. The names usually contain hashes, for example:

```text
index.html
app.<hash>.js          # webpack runtime / chunk map
<video-chunk>.<hash>.js
<player-chunk>.<hash>.js
```

Search the active files for the old ArtPlayer version string and the video component's module. Confirm these are the files served by the page; stale files elsewhere on disk do not affect the running UI.

Record the originals and checksums before editing:

```sh
sudo cp -a /path/to/frontend /path/to/frontend.backup-$(date +%Y%m%d-%H%M%S)
sha256sum /path/to/frontend/index.html /path/to/frontend/*.js
```

Adjust the backup command to copy only the frontend files if the whole directory is large. Verify the destination and the resulting backup before proceeding.

## Patch approach

The bundle is minified webpack output, so patch the module bodies carefully and keep each edit narrow:

1. **Update the ArtPlayer module.** Replace the bundled ArtPlayer 4 implementation with the official ArtPlayer 5 browser build, preserving the webpack module's exports shape expected by the video component. Check the package's UMD/browser build and how the existing module exports its constructor before editing.
2. **Keep Vue-APlayer from crashing the shared chunk.** In the affected legacy module, the old code reads the default Vue import's `.version`. ReCasaOS's Vue 3 bundle may expose `version` on the namespace instead. Use a guarded version lookup equivalent to:

   ```js
   vueNamespace.version || vueDefault.version
   ```

   Adapt variable names to the exact minified module. Do not apply a blind text replacement across all bundles.
3. **Add the subtitle setting to the video component.** Use ArtPlayer's documented settings API to list subtitle tracks discovered for the current video. Include an `Off` option and an option for each supported sidecar file. On selection, call the documented subtitle switching API with the subtitle URL, format, and language/label. Keep the component's existing video URL and lifecycle handling intact.
4. **Use cache-busted output names.** Give modified chunks new hash-like filenames (or otherwise ensure cache invalidation), update the webpack runtime's chunk-to-filename mapping, and update `index.html` to load the new runtime. Keep the mapping and filenames consistent. The runtime must point at the exact files present on disk.
5. **Check syntax before replacing live files.** Run `node --check` on each modified JavaScript file. Then compare the modified bundle to the backup and confirm the expected markers are present.

ArtPlayer's current documentation for the [settings component](https://artplayer.org/document/en/component/setting) and [subtitle support](https://artplayer.org/document/en/advanced/built-in) describes the public APIs. Confirm API names and option shapes against the version you install.

## Install the prepared patch with the script

The repository includes [`install-artplayer-patch.sh`](./install-artplayer-patch.sh). It checks JavaScript syntax and the HTML/runtime chunk references, backs up the live files under `/var/backups`, then installs the four prepared files. It requires Bash, Node.js, and `sudo` on the ReCasaOS server.

The script handles **validation, backup, and deployment**. It does not synthesize a patched webpack bundle: the ArtPlayer module, Vue compatibility guard, and subtitle setting still need to be adapted to the exact frontend build as described above. ReCasaOS bundles are minified and build-specific, so automatic text substitutions against an unknown build could corrupt the dashboard. Prepare a directory containing the complete, matching set:

```text
patched-assets/
  index.html
  app.NEW_HASH.js
  video.NEW_HASH.js
  player.NEW_HASH.js
```

Copy the script and prepared assets to the server (or clone the guide repository), make the script executable, and find the live web root and the actual filenames as described in “Find the active bundles.” Then run, substituting the real paths and filenames:

```sh
chmod +x ./install-artplayer-patch.sh
sudo ./install-artplayer-patch.sh \
  --web-root /path/to/frontend \
  --assets-dir /path/to/patched-assets \
  --runtime app.NEW_HASH.js \
  --video-chunk video.NEW_HASH.js \
  --player-chunk player.NEW_HASH.js
```

The script installs chunks and runtime first and `index.html` last. It prints the backup directory, normally `/var/backups/recasaos-artplayer-<timestamp>`. Keep that backup until all verification passes. The script does not restart services because this is a static frontend update; a hard refresh is required.

If the script rejects the assets, stop and correct the staged set; do not bypass its checks. If you need to roll back, restore the backed-up files as root:

```sh
sudo cp -a /var/backups/recasaos-artplayer-<timestamp>/. /path/to/frontend/
```

Use the actual backup path printed by the script and the same web root used during installation.

## Deploy and verify

1. Copy the staged files into the active frontend directory, preserving ownership and permissions. Keep the original backup until the UI has been checked.
2. If the frontend is served from a cache or service worker, clear/invalidate it as appropriate. Open ReCasaOS in a private window or use a hard refresh with browser cache disabled.
3. In DevTools **Network**, verify the page requests the new runtime and both modified chunks (HTTP 200). Confirm the old chunk URLs are no longer the active entry points.
4. In DevTools **Console**, check for JavaScript errors. In particular, confirm the undefined Vue `version` error is gone.
5. Open a video with a matching external subtitle file in the same folder, such as `Example.mp4` and `Example.en.srt` (or another extension supported by your implementation).
6. Open player settings. Confirm the subtitle menu lists `Off` and the matching subtitle. Select the subtitle and confirm the player reports it as active. If possible, verify an actual caption is rendered at a known timestamp; a selected menu item alone does not prove that the subtitle content loaded correctly.
7. Test a video with no matching subtitles and confirm playback still works and the menu allows subtitles to be off.

## Rollback

If the UI fails to load, the player crashes, or the new assets return 404:

1. Restore `index.html`, the webpack runtime, and all modified chunks from the timestamped backup as one set.
2. Confirm the runtime references the restored chunk filenames.
3. Hard-refresh the browser with cache disabled and verify the original player loads.

Do not leave a mixture of the old runtime and new chunks (or the reverse); mismatched chunk maps commonly produce startup errors.

## Maintenance notes

- This is a frontend bundle patch, not a supported ReCasaOS setting. A ReCasaOS/CasaOS frontend update can replace it; keep the backup and this procedure, then re-check the new bundle before reapplying.
- Hashed filenames and webpack module IDs are build-specific. Re-discover them after every frontend update; never assume the sample installation's names apply elsewhere.
- “Latest” changes over time. Choose and test an explicit ArtPlayer release, and update this guide's tested version when the procedure is revalidated.
- Avoid publishing server addresses, credentials, private media paths, or other machine-specific details in a public repository.
