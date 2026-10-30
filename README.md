# MacDownloader (IDM Alternative for Apple Silicon Mac Mini M4)

A high-performance, native macOS download accelerator engineered specifically for Apple Silicon (M4 / arm64) with full companion Google Chrome extension integration.

Inspired by the architecture of **Internet Download Manager (IDM)**, this system delivers multi-segment parallel accelerated downloads, pause/resume state management, real-time chunk visualization, and media stream sniffing for videos and audio.

---

## 🌟 Key Features

### 🚀 Native macOS App (SwiftUI & Apple Silicon Native)
- **Multi-Connection Segmented Acceleration**: Partitions downloads into parallel worker chunks (configurable to 1, 4, 8, 16, or 32 connections) using HTTP `Range: bytes=` requests.
- **IDM-Style Segment Visualizer Bar**: Dynamic multi-color connection bar displaying the real-time download progress of each individual byte chunk.
- **Smart Pause & Resume**: Saves chunk offsets and byte markers. Resumes downloads without losing completed segments.
- **Automatic Category Sorting**: Automatically classifies downloads into Video, Audio, Compressed (Zip/DMG), Documents, and Other.
- **Local Extension Bridge (Zero-Config)**: Embedded lightweight HTTP daemon running on `127.0.0.1:45678` using Apple's `Network.framework` (`NWListener`). No complex Native Messaging manifests required.
- **Queue Management**: Auto-starts downloads, respects maximum concurrent download limits, and persists task states across application restarts.

### 🌐 Google Chrome Extension (Manifest V3)
- **Floating Media Download Overlay**: Detects HTML5 `<video>` and `<audio>` elements on any webpage and renders an IDM-style hovering download pill in the top-right corner.
- **Network Stream Sniffer**: Background service worker monitors HTTP responses for media MIME types (`video/mp4`, `video/webm`, `application/x-mpegURL`, `audio/mpeg`, etc.).
- **Popup Media Hub**: Shows all media files and streams detected on the active browser tab with one-click download buttons.
- **Context Menu Integration**: Right-click any link, video, audio, or image -> "Download with MacDownloader".
- **Instant Dispatch**: Transmits the media URL, document title, page referrer, and user-agent directly to `MacDownloader.app`.

---

## 📁 Project Structure

```
MacDownloader/
├── MacDownloader.app/               # Compiled & code-signed standalone macOS Application
├── Sources/
│   └── MacDownloader/
│       ├── MacDownloader.swift      # App entry point & NSApplicationDelegate
│       ├── Models/
│       │   ├── DownloadItem.swift   # Task model & categories
│       │   └── DownloadSegment.swift# Individual chunk range model
│       ├── Engine/
│       │   ├── SegmentedDownloader.swift # Parallel HTTP chunk fetcher & file merger
│       │   └── DownloadManager.swift     # Queue manager & persistence
│       ├── Server/
│       │   └── LocalApiServer.swift      # Embedded NWListener HTTP bridge (127.0.0.1:45678)
│       └── Views/
│           ├── ContentView.swift         # Main NavigationSplitView & status bar
│           ├── SidebarView.swift         # Categories & status filters with badges
│           ├── DownloadRowView.swift     # List item with IDM segment visualizer
│           ├── SegmentVisualizerView.swift# Multi-chunk graphical progress bar
│           ├── NewDownloadSheet.swift    # Add URL sheet with auto-clipboard check
│           ├── NewDownloadViewModel.swift# Clean MVVM form model
│           ├── DownloadDetailSheet.swift # Detailed chunk inspector
│           └── SettingsView.swift        # Preferences & acceleration limits
├── Extension/
│   ├── manifest.json                # Manifest V3 specification
│   ├── content.js                   # Video/audio player overlay injection
│   ├── overlay.css                  # Floating button styles
│   ├── background.js                # Web request sniffer & context menus
│   ├── popup.html                   # Extension popup UI
│   ├── popup.js                     # Sniffed media display & status checking
│   ├── popup.css                    # Dark mode popup stylesheet
│   └── icons/                       # App and extension icons (16, 48, 128)
├── Scripts/
│   └── build_app.sh                 # Release compilation & bundle packager
└── Package.swift                    # Swift Package Manager configuration
```

---

## 🛠 How to Use

### 1. Launching the Mac Application
The pre-compiled app is located in `MacDownloader.app`. You can launch it directly from Terminal:
```bash
open /Users/abishekwork/.gemini/antigravity/scratch/MacDownloader/MacDownloader.app
```
*(Or drag `MacDownloader.app` into your macOS `/Applications` folder.)*

To re-build or modify the code:
```bash
cd /Users/abishekwork/.gemini/antigravity/scratch/MacDownloader
./Scripts/build_app.sh
```

### 2. Installing the Google Chrome Extension
1. Open Google Chrome and navigate to:
   ```
   chrome://extensions
   ```
2. In the top-right corner, turn ON **Developer mode**.
3. In the top-left corner, click **Load unpacked**.
4. In the file dialog, choose the `Extension` directory:
   ```
   /Users/abishekwork/.gemini/antigravity/scratch/MacDownloader/Extension
   ```
5. The **MacDownloader** icon will appear in your Chrome toolbar.
6. Open any webpage containing videos or audio (e.g. YouTube, Vimeo, HTML5 video). A floating **"Download Video"** button will hover over the video. Clicking it immediately dispatches the file to your Mac app!
