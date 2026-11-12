# FETCHDECK
> **[Your downloads, all in one place.]**  
> *Vibecoded by Abishek [@brozhero](https://github.com/brozhero)*

---

**FETCHDECK** is a high-performance, native macOS media accelerator engineered for Apple Silicon (M-Series / arm64) with macOS Sequoia glassmorphic aesthetics and a companion Chrome extension.

Inspired by the speed of **Internet Download Manager (IDM)** and the media aesthetics of **Downie**, FETCHDECK combines multi-chunk parallel download acceleration, automatic audio extraction, live video thumbnails, universal support for 1,000+ websites, and seamless sleep/wake reconnection into a unified, fluid experience.

---

## ✨ Highlights & Features

### 💎 macOS Sequoia Glassmorphic Aesthetics
- Translucent `.ultraThinMaterial` backgrounds, rounded cards, and glowing accent borders.
- Custom macOS glassmorphic app icon rendered natively for Retina and Dock displays.
- Segmented status badges with glowing resolution pills (4K, 1080p, 720p, 360p, MP3).

### 🎬 Rich Video Thumbnails (The Downie Effect)
- High-definition 16:9 video preview thumbnails rendered asynchronously for every stream.
- Inset duration badges (e.g. `03:45`) and channel/creator metadata badges.
- Instant fallback resolution using YouTube high-res poster caches.

### 🌐 Universal 1,000+ Site Support
- One-click downloads for **YouTube, TikTok, Instagram Reels, Twitter/X, Reddit, Vimeo, SoundCloud**, and generic HLS/DASH/MP4 web streams.
- Client challenge resolver with embedded Node.js runtime and InnerTube fallback strategies.

### 🎵 1-Click Audio Extraction Presets
- Convert and extract any video stream into **High-Quality MP3 (320 kbps)** or **Original M4A Audio** via built-in FFmpeg processing.
- Available directly from the "Add Download" modal and via right-click contextual menus on completed videos.

### ⚡ IDM-Grade Multi-Segment Parallel Acceleration
- Splits files into 1, 4, 8, 16, or 32 concurrent HTTP range chunks.
- **Segment Visualizer**: Real-time graphical visualization of active chunks downloading in parallel.
- Resilient byte-level pause and resume capabilities.

### 🔄 Automatic Engine Self-Updater
- Keep video extractors current with single-click updates in Settings and About sheets.
- Directly invokes `yt-dlp -U` with version reporting and status monitoring.

### 🌙 Smart Sleep & Network Reconnection
- **Auto-Pause on Sleep**: Catches `NSWorkspace.willSleepNotification` and safely suspends all active chunk streams.
- **Auto-Resume on Wake**: Debounces 3 seconds on `NSWorkspace.didWakeNotification` to allow Wi-Fi adapters to reconnect, then seamlessly resumes queued and downloading files.
- **Live Network Monitor**: Employs `NWPathMonitor` to detect dropouts and automatically retry interrupted connections.

---

## 🏗️ Architecture

```
FETCHDECK/
├── FetchDeck.app/                   # Standalone compiled and signed macOS application
├── Sources/MacDownloader/
│   ├── MacDownloader.swift          # App entry point & NSApplicationDelegate
│   ├── Models/
│   │   ├── DownloadItem.swift       # Download item model with thumbnails & duration
│   │   └── DownloadSegment.swift    # Byte chunk model
│   ├── Engine/
│   │   ├── SegmentedDownloader.swift# Multi-chunk HTTP range downloader
│   │   ├── DownloadManager.swift    # Queue, sleep/wake, NWPathMonitor, MP3 conversion
│   │   └── YouTubeResolver.swift    # Universal yt-dlp & InnerTube extraction engine
│   ├── Server/
│   │   └── LocalApiServer.swift     # Embedded zero-config HTTP daemon (127.0.0.1:45678)
│   └── Views/
│       ├── ContentView.swift        # Main NavigationSplitView
│       ├── SidebarView.swift        # Category filter with live engine version & network status
│       ├── DownloadRowView.swift    # Downie-style card with thumbnail & segment visualizer
│       ├── SegmentVisualizerView.swift# Multi-threaded chunk bar
│       ├── NewDownloadSheet.swift   # Glassmorphic URL modal with Audio Presets
│       ├── AboutView.swift          # Glassmorphic about sheet with creator credits
│       └── SettingsView.swift       # Preferences and Engine Updater
├── Extension/
│   ├── manifest.json                # Chrome Manifest V3
│   ├── content.js                   # Universal in-page floating FetchDeck button
│   ├── overlay.css                  # Sequoia glassmorphic floating pill styles
│   ├── background.js                # Media stream sniffer & local bridge dispatcher
│   ├── popup.html                   # Extension popup hub
│   └── icons/                       # App and extension icons (16, 48, 128)
├── Scripts/
│   └── build_app.sh                 # Native Apple Silicon release compilation script
└── Package.swift                    # Swift Package Manager configuration
```

---

## 🚀 Getting Started

### 1. Launching FETCHDECK
The compiled application is located in your Applications folder and workspace:
```bash
# Launch directly from Applications:
open ~/Applications/FetchDeck.app

# Or from the workspace build:
open FetchDeck.app
```

To recompile or package from source:
```bash
./Scripts/build_app.sh
```

### 2. Installing the Chrome / Chromium Extension
1. Open Google Chrome (or Brave / Edge) and visit: `chrome://extensions`
2. Toggle on **Developer mode** in the top-right corner.
3. Click **Load unpacked** in the top-left corner.
4. Select the `Extension` folder:
   ```
   MacDownloader/Extension
   ```
5. Navigate to any video site (e.g. YouTube, Vimeo, TikTok, Instagram, Twitter/X, Reddit).
6. Click the hovering **FetchDeck** button to choose your resolution, or use the extension toolbar popup.

### 3. Installing the Opera Companion Extension
1. Open **Opera Browser** on your Mac.
2. In the Opera address bar, navigate to:
   ```
   opera://extensions
   ```
3. In the top-right corner, turn ON the **Developer mode** toggle.
4. Click the **Load unpacked** button in the top-left.
5. In the file picker, select the `Extension-Opera` folder (or `Extension`):
   ```
   MacDownloader/Extension-Opera
   ```
6. The **FetchDeck** icon will appear in your Opera toolbar and the hovering download pill will automatically appear over videos on **any website**!

---

## 🛡️ License

Released under the MIT License. Crafted with precision for macOS Sequoia.

**FETCHDECK** — Vibecoded by Abishek [@BroZHERO](https://github.com/BroZHERO).
