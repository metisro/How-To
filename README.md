# How-To
 
Collection of how-to's which might come handy.
 
Each guide lives in the [`howto`](howto/) folder and is written to be followed step by step from a terminal. Every guide lists what it was tested on, how to back up, and how to roll back.
 
## Guides
 
| Guide | What it does | Tested on |
|---|---|---|
| [Upgrade the CasaOS video player and add a subtitle selector](howto/CasaOS-v0.4.1.5-ArtPlayer-upgrade-guide.md) | Upgrades the built-in ArtPlayer (4.6.2 → 5.x) by patching the built web UI, and adds a **Subtitle** selector to the player settings that picks up `.srt`, `.vtt` and `.ass` files stored next to the video. No source rebuild needed. | CasaOS v0.4.15, Ubuntu |
 
## Using the guides
 
1. Read the guide from top to bottom before running anything.
2. Take the backups it describes. Most guides modify files that are owned by root.
3. Check that your version matches what the guide was tested on. If it does not, the scripts are written to abort without changing anything when their markers are not found.
> These guides are provided as is, without warranty. You are responsible for your own systems, so keep your backups.
 
## Feedback and contributions
 
- Something does not work on your version? [Open an issue](../../issues) with your version and the console or terminal output.
- Tested a guide on another version or setup? Let me know and I will add it to the "Tested on" column.
- Improvements and fixes are welcome as pull requests.
## License
 
Released under the [GPL-3.0 license](LICENSE).
