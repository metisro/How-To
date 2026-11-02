# Upgrade the CasaOS v0.4.1.5 video player (ArtPlayer 4.6.2 → 5.x) and add subtitle selection
 
CasaOS v0.4.15 ships its Files app with a video player built on **ArtPlayer 4.6.2**. This guide shows how to:
 
1. **Upgrade ArtPlayer to 5.x** by patching the already-built web UI (no source rebuild needed).
2. **Add a "Subtitle" selector** to the player settings, which picks up `.srt`, `.vtt` and `.ass` files stored next to the video.
> **Tested on:** CasaOS v0.4.15, Ubuntu server, Node.js and npm installed on the host.
> **Not affiliated with** IceWhale/CasaOS or ArtPlayer. Use at your own risk and keep backups.
 
---
 
## Background
 
CasaOS serves its UI from `/var/lib/casaos/www`. It is a webpack **development-style** build, so the JavaScript chunks are not minified: modules are readable strings wrapped in `eval(...)`. That makes it possible to replace a single module in place.
 
Two chunks matter:
 
| Chunk (glob) | What it holds |
|---|---|
| `vendors-node_modules_pnpm_artplayer_4_6_2_*.js` | The ArtPlayer 4.6.2 library, plus hls.js, music-metadata, vue-aplayer and others |
| `src_components_filebrowser_viewers_VideoPlayer_vue.*.js` | The CasaOS component that creates the player and passes its options |
 
The hashes in the file names differ between installs, so the commands below use globs instead of the exact names.
 
### Why there is no subtitle button by default
 
ArtPlayer only shows subtitle controls when it is given a `subtitle` option with a URL. The stock CasaOS component never passes one. The **Subtitle offset** item you may see in the settings comes from `subtitleOffset: true`, and it does nothing without a loaded subtitle. Patch 2 below fixes this.
 
---
 
## Requirements
 
- SSH access to the CasaOS host with `sudo`
- `node` and `npm` on the host (`node --version`)
- Internet access from the host (to download the package from npm)
---
 
## 0. Back up
 
```bash
cd /var/lib/casaos/www
 
F=$(ls vendors-node_modules_pnpm_artplayer_4_6_2_*.js)
V=$(ls src_components_filebrowser_viewers_VideoPlayer_vue.*.js)
echo "$F"; echo "$V"        # both must print exactly one file name
 
mkdir -p ~/casaos-www-backup
sudo cp -a "$F" "$V" ~/casaos-www-backup/
```
 
> The same files also appear inside Docker `overlay2` layers on some systems. Ignore those and patch the host path `/var/lib/casaos/www`.
 
---
 
## 1. Upgrade ArtPlayer
 
### 1.1 Download a 5.x build from npm
 
```bash
cd /tmp
npm view artplayer version            # latest published version
 
VER=5.4.0                              # use the version printed above, or pin one
rm -rf ap && mkdir ap && cd ap
npm pack artplayer@$VER && tar xzf artplayer-$VER.tgz
ls -l package/dist/artplayer.js        # the UMD build we need
```
 
### 1.2 Create the patch script
 
This replaces only the ArtPlayer module inside the vendors chunk and leaves every other module (hls.js, etc.) untouched.
 
```bash
cat > /tmp/patch-artplayer.js <<'EOF'
const fs = require('fs');
const [,, chunkPath, artPath, outPath] = process.argv;
const src = fs.readFileSync(chunkPath, 'utf8');
const art = fs.readFileSync(artPath, 'utf8');
 
const startKey = '"./node_modules/.pnpm/artplayer@4.6.2/node_modules/artplayer/dist/artplayer.js":';
const nextKey  = ',"./node_modules/.pnpm/content-type@1.0.5/node_modules/content-type/index.js":';
const fnHead   = 'function(module,__unused_webpack_exports,__webpack_require__){eval(';
 
const s = src.indexOf(startKey);
const e = src.indexOf(nextKey, s);
const f = src.indexOf(fnHead, s);
if (s < 0 || e < 0 || f < 0 || f > e) throw new Error('markers not found, aborting');
 
const code = art + '\n//# sourceURL=webpack://casaos-main/./node_modules/artplayer/dist/artplayer.js';
const lit = JSON.stringify(code).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
const fn = 'function(module,exports,__webpack_require__){eval(' + lit + ')}';
 
fs.writeFileSync(outPath, src.slice(0, f) + fn + src.slice(e));
console.log('replaced', e - f, 'bytes with', fn.length);
EOF
```
 
### 1.3 Build and install the patched chunk
 
```bash
cd /var/lib/casaos/www
node /tmp/patch-artplayer.js "$F" /tmp/ap/package/dist/artplayer.js /tmp/vendors_patched.js
node --check /tmp/vendors_patched.js && echo "syntax OK"
 
# only run this if both lines above succeeded:
sudo cp /tmp/vendors_patched.js "$F"
```
 
Hard-refresh the browser (**Ctrl+Shift+R**). If it still looks like the old version, open DevTools → Network → tick **Disable cache**, because the file name did not change.
 
Open any video and check the console. ArtPlayer prints its version on startup, and it should now read `5.x`.
 
---
 
## 2. Add the subtitle selector
 
### 2.1 How it works
 
The video component receives a `list` prop (the files in the current folder). The patch:
 
1. Takes the video's file name without extension (`Movie.2024.mkv` → `movie.2024`).
2. Finds files in `list` that start with that name and end in `.srt`, `.vtt` or `.ass`.
3. Adds a **Subtitle** item to the settings panel with *Off* plus one entry per file. The label is whatever follows the base name, so `Movie.2024.en.srt` shows as `en`.
4. Loads the chosen file with `art.subtitle.switch(...)`, so **Subtitle offset** now works too.
Videos without matching subtitle files behave exactly as before.
 
### 2.2 Create the patch script
 
```bash
cat > /tmp/patch-subs.js <<'EOF'
const fs = require('fs');
const [,, inPath, outPath] = process.argv;
let src = fs.readFileSync(inPath, 'utf8');
if (src.includes('[subs]')) throw new Error('already patched');
 
const code = `
try {
  const art = this.instance;
  const dot = this.item.name.lastIndexOf(".");
  const base = (dot > 0 ? this.item.name.slice(0, dot) : this.item.name).toLowerCase();
  const all = this.list || [];
  const subs = all.filter(f => f && f.name && /\\.(srt|vtt|ass)$/i.test(f.name) && f.name.toLowerCase().startsWith(base));
  console.debug("[subs] matches:", subs.map(f => f.name), "| list size:", all.length);
  if (subs.length) {
    const items = subs.map(f => ({
      html: f.name.slice(base.length).replace(/^[._ -]+/, "") || f.name,
      file: f
    }));
    art.setting.add({
      name: "zm-subtitle",
      width: 250,
      html: "Subtitle",
      tooltip: "Off",
      selector: [{ html: "Off", off: true }].concat(items),
      onSelect: (it) => {
        if (it.off) { art.subtitle.show = false; return "Off"; }
        const ext = it.file.name.split(".").pop().toLowerCase();
        Promise.resolve(art.subtitle.switch(this.getFileUrl(it.file), { name: it.html, type: ext }))
          .then(() => { art.subtitle.show = true; });
        return it.html;
      }
    });
  }
} catch (e) { console.warn("[subs] failed", e); }
`;
// make it safe inside a single-quoted JS string literal
const esc = code.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\r?\n/g, '\\n');
 
const marker = 'lang: this.$i18n.locale.replace(';
if (src.split(marker).length !== 2) throw new Error('marker not unique/found');
const i = src.indexOf(marker);
const j = src.indexOf('});', i);
if (j < 0 || j - i > 200) throw new Error('constructor end not found');
src = src.slice(0, j + 3) + esc + src.slice(j + 3);
fs.writeFileSync(outPath, src);
console.log('patched, inserted', esc.length, 'chars');
EOF
```
 
### 2.3 Build and install
 
```bash
cd /var/lib/casaos/www
node /tmp/patch-subs.js "$V" /tmp/videoplayer_patched.js
node --check /tmp/videoplayer_patched.js && echo "syntax OK"
 
# only run this if both lines above succeeded:
sudo cp /tmp/videoplayer_patched.js "$V"
```
 
Hard-refresh again, then open a video that has a subtitle file next to it, for example:
 
```
Movie.2024.mkv
Movie.2024.en.srt
Movie.2024.cs.srt
```
 
Open **Settings (gear) → Subtitle** and choose a language.
 
---
 
## Rollback
 
```bash
cd /var/lib/casaos/www
sudo cp -a ~/casaos-www-backup/* .
```
 
Then hard-refresh the browser.
 
---
 
## Troubleshooting
 
Open the browser DevTools console and look for the debug line `[subs] matches: [...] | list size: N`.
 
| Symptom | Likely cause / fix |
|---|---|
| `matches` is empty but `list size` is above 1 | Subtitle names do not start with the video's base name. Rename them to `<video name>.<anything>.srt`. |
| `list size` is 1 | The folder listing is not passed to the player in your setup. Open an issue with your CasaOS version. |
| Subtitle selector appears but no text is shown | Check the console for a `[subs] failed` message or a network error loading the subtitle URL. |
| Garbled accented characters (common with Central/Eastern European `.srt` files) | The file is not UTF-8. Convert it to UTF-8, or add `encoding: "windows-1250"` (or the right charset) to the options passed to `art.subtitle.switch(...)`. |
| `... is not a constructor` after step 1 | The build you installed does not export the class the way 4.x did. Try another 5.x version, or open an issue with the version and console output. |
| Everything looks unchanged | Browser cache. Hard-refresh and disable the cache in DevTools. |
 
---
 
## Limitations
 
- **Embedded subtitles** (tracks inside MKV or MP4 files) are not detected. Browsers cannot read them; they would need to be extracted with `ffmpeg` on the server.
- **The patch is lost on CasaOS updates**, because the UI files are replaced. Keep the two scripts and re-run them afterwards. The marker strings may change in newer CasaOS builds, in which case the scripts abort without writing anything.
- Only the video component is patched; the audio player (vue-aplayer) is unaffected.
---
 
## Notes
 
- Both scripts write to a temporary file and run `node --check` before anything under `/var/lib/casaos` is modified.
- ArtPlayer is MIT-licensed: <https://github.com/zhw2590582/ArtPlayer>
- CasaOS UI source: <https://github.com/IceWhaleTech/CasaOS-UI>
