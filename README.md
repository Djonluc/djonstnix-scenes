![Scenes](https://i.imgur.com/eUR724l.png)

# Scenes
This resource enhances the scenes experience within QBCore and Qbox. It now supports branded previewing, FiveManage-hosted image mirroring, live placement preview, owner/admin permissions, editable scenes, custom fonts, and text effects.

- Ban someone from creating scenes: `/sceneban [playerId]`
- Open the scenes menu: `/scene`
- Preview an image before creating a scene: `/scenepreview [image URL or local path]`

## Dependencies
- [ox_lib](https://github.com/overextended/ox_lib/releases)

## Installation
1. Clone this repository and place the files into your designated resources folder.
2. Rename the script folder to `djonstnix-scenes`.

## Feature Highlights
- DjonStNix-branded image preview overlay
- Live in-world placement preview with mouse-wheel resizing
- Optional scene timers for temporary scenes
- Owner-only edit/delete permissions with admin override
- Edit nearest scene instead of deleting and recreating it
- Built-in Tenor media browser for scene images
- FiveManage mirroring for player-provided image URLs
- Automatic image preloading when players get near scenes
- More GTA font choices, text effect presets, and text animation presets
- Background-free text rendering with outline, shadow, neon, and ghost styles
- Default hotkey support through `F7` via key mapping

## Image Hosting
This resource follows the same general idea used by phone/gallery scripts: upload or mirror the image first, then store the hosted URL.

### Recommended: FiveManage
This is the best route for player-created scene images because the final saved URL is hosted on a FiveM-friendly media service instead of a random third-party site. The script mirrors pasted image URLs to FiveManage and stores the returned hosted URL.

Official docs:
- [FiveManage Home](https://fivemanage.com/)
- [FiveManage Docs](https://docs.fivemanage.com/)
- [FiveManage Uploading Images Guide](https://docs.fivemanage.com/guides/uploading-files/images)
- [FiveManage API Reference](https://docs.fivemanage.com/api-reference/introduction)
- [FiveManage Quickstart](https://docs.fivemanage.com/quickstart)
- [qb-phone repository](https://github.com/qbcore-framework/qb-phone)

### Setup
1. Create a FiveManage account and generate a token with `Images` or `Media` scope.
2. Add this to your `server.cfg`:

```cfg
set djonstnix-scenes:fivemanageApiKey YOUR_MEDIA_API_KEY
```

3. Restart `djonstnix-scenes`.
4. Players can now paste a direct image URL into `/scene`.
5. The server downloads that image, uploads it to FiveManage through the base64 upload endpoint, and stores the returned hosted URL in the scene data.

### Optional Media Browser: Tenor
This resource now includes a built-in Tenor browser so players can search for GIFs from the scene menu instead of pasting every link manually.

Add this to your `server.cfg`:

```cfg
set djonstnix-scenes:tenorApiKey YOUR_TENOR_API_KEY
```

Then restart `djonstnix-scenes` and use `Browse Media` from the scene menu.

### Important Notes
- The pasted link should be a direct image file URL such as `.png`, `.jpg`, `.jpeg`, `.webp`, or `.gif`.
- The final scene does not keep using Imgur, Discord, or random hosts after a successful upload. It stores the FiveManage URL returned by the API.
- Local staff-managed files inside `ui/images/` still work and are useful for fixed server posters or signs.
- The default maximum remote image size is `8 MB`. You can change this in `shared/config.lua`.

### Config
Key options in `shared/config.lua`:
- `mirrorExternalUrlsToFivemanage = true`
- `allowDirectRemoteUrls = false`
- `allowedStoredHosts = { 'r2.fivemanage.com', '*.fivemanage.com', 'i.fmfile.com', '*.fmfile.com' }`
- `defaultImageScale = 2.25`
- `defaultTextScale = 0.48`
- `ScenePermissions.adminGroups = { 'god', 'admin' }`
- `SceneUI.defaultKey = 'F7'`

This means player-pasted links are mirrored to FiveManage first, and the scene only keeps trusted hosted image URLs afterward.

## Ownership Rules
- The scene creator can edit or destroy their own scene.
- Admin groups configured in `Config.ScenePermissions.adminGroups` can edit or destroy any scene.
- Legacy scenes without a stored owner identifier may need to be recreated if you want non-admin ownership editing on them.

## Styling
Text scenes support:
- Multiple GTA font presets
- Pulse, float, flicker, glitch, and breathe animations
- Clean, outline, shadow, neon, ghost, premium, and warning text effects
- Adjustable text size
- No forced dark background rectangle behind the text

Image scenes support:
- Automatic aspect-ratio fitting based on the loaded image
- Auto-size adjustments after preview when the player keeps the default image size
- Adjustable size during creation and editing
- Preloading before the player reaches render distance
- Live placement preview before confirming the location

Timers:
- Set `Timer (Minutes)` to `0` to keep the scene permanently
- Set any positive minute value to let the server automatically remove the scene later

## Showcase
![/scene](https://i.imgur.com/OFwxsMi.png)
![Create Scene](https://i.imgur.com/wg7OD3Z.png)

## Community
[![Discord](https://discord.com/api/guilds/1075048579758035014/widget.png?style=banner2)](https://discord.gg/cFuv5BMWzK)
