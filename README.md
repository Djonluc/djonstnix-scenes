# 🎬 DjonStNix Scenes

**Elevate your FiveM server with the industry-standard in-world scene system. Built for QBCore & Qbox.**

DjonStNix Scenes is a high-performance, feature-rich resource designed to make your server feel alive through persistent, customizable in-world text and image scenes. Whether it's promotional posters, crime scene markers, or server announcements, this system provides the tools to build immersive experiences.

---

## 🚀 Key Features

### 🖼️ Elite Image Rendering (Pixel-Perfect)

- **Unlimited Resolution**: Removed all internal size caps. Render images in their native 4K/8K quality in-world.
- **Universal Aspect-Ratio Persistence**: Perfect 1:1 shape-matching for Portrait, Landscape, and Square assets.
- **Screen Proportional Calibration**: Automatically compensates for widescreen/ultrawide monitor distortion.
- **Unique Memory Isolation**: Advanced TXD hashing prevents image collisions and "resolution bleeding."
- **FiveManage Mirroring**: Securely mirror player-pasted URLs to stable FiveManage hosting automatically.
- **Integrated GIF Browser**: Instant Tenor media discovery directly from the scene creation menu.

### ✍️ Premium Typography

- **GTA Font Presets:** Access multiple native styles from Standard to Pricedown.
- **Cinematic Effects:** Apply Outline, Shadow, Neon, Ghost, and Premium styling.
- **Dynamic Animations:** Bring text to life with Pulse, Float, Flicker, Glitch, and Breathe effects.
- **Background-Free:** Clean rendering that blends perfectly into the environment.

### 🛠️ Developer & Staff Tools

- **Live Placement Preview:** Real-time 3D placement with mouse-wheel scaling before you commit.
- **Persistent Storage:** Scenes are saved to JSON and restored instantly on resource start.
- **Precise Permissions:** Integrated License-based ownership and Admin group overrides.
- **In-Game Management:** Toggle visibility, edit existing scenes, or destroy them with ease.
- **Exploit Protection:** Built-in banning system and URL validation.

---

## 🔧 Installation & Setup

1. **Download:** Place the files into your `resources/[addons]` folder.
2. **Rename:** Ensure the folder name is exactly `djonstnix-scenes`.
3. **Configure:** Set your API keys in your `server.cfg` for full functionality.

### 📡 FiveManage Integration (Recommended)

FiveManage is used to securely host player-uploaded images, ensuring stability and performance.

1. Create an account at [FiveManage](https://fivemanage.com/).
2. Add your API key to `server.cfg`:
   ```cfg
   set djonstnix-scenes:fivemanageApiKey "YOUR_API_KEY"
   ```

### 🔍 Tenor Media Browser

Enable players to search for GIFs directly in-game.

1. Get a V2 API key from Google Cloud Console (Tenor API).
2. Add it to `server.cfg`:
   ```cfg
   set djonstnix-scenes:tenorApiKey "YOUR_API_KEY"
   ```

---

## 🎮 Commands & Controls

| Command               | Description                                |
| :-------------------- | :----------------------------------------- |
| `/scene`              | Open the main creation and management menu |
| `/scenepreview [URL]` | Quickly preview an image in-world          |
| `/sceneban [ID]`      | (Admin) Ban a player from creating scenes  |

**Default Keybind:** `F7` (Customizable in FiveM settings).

---

## 📂 Configuration

Global settings can be found in `shared/config.lua`:

- `defaultImageScale`: 2.5
- `defaultDistance`: 7.5
- `adminGroups`: {'god', 'admin'}
- `allowLocalFiles`: true (Access files in `ui/images/`)

---

## 💡 Why DjonStNix?

_"Built for creators who want their server to actually feel alive."_

We don't just script... **we build experiences.**

> [!NOTE]
> All systems follow the **User → Client → Server → Validation → Server → Client → UI** integrity loop. Zero trust in client input, maximum performance for 100+ players.

---
