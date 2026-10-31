const API_ENDPOINT = "http://127.0.0.1:45678/api/download";
const STATUS_ENDPOINT = "http://127.0.0.1:45678/api/status";

// Cache for captured media per tab: tabId -> Array of MediaItems
const tabMediaMap = new Map();

// Extensive YouTube itag dictionary with human-friendly labels and dimensions
const YOUTUBE_ITAGS = {
  18: { quality: "360p", dimensions: "640×360", format: "MP4 Video", type: "video", combined: true },
  22: { quality: "720p HD", dimensions: "1280×720", format: "MP4 Video", type: "video", combined: true },
  137: { quality: "1080p Full HD", dimensions: "1920×1080", format: "MP4 Video", type: "video", combined: false },
  136: { quality: "720p HD", dimensions: "1280×720", format: "MP4 Video", type: "video", combined: false },
  135: { quality: "480p", dimensions: "854×480", format: "MP4 Video", type: "video", combined: false },
  134: { quality: "360p", dimensions: "640×360", format: "MP4 Video", type: "video", combined: false },
  133: { quality: "240p", dimensions: "426×240", format: "MP4 Video", type: "video", combined: false },
  160: { quality: "144p", dimensions: "256×144", format: "MP4 Video", type: "video", combined: false },
  248: { quality: "1080p Full HD", dimensions: "1920×1080", format: "WebM Video", type: "video", combined: false },
  247: { quality: "720p HD", dimensions: "1280×720", format: "WebM Video", type: "video", combined: false },
  244: { quality: "480p", dimensions: "854×480", format: "WebM Video", type: "video", combined: false },
  243: { quality: "360p", dimensions: "640×360", format: "WebM Video", type: "video", combined: false },
  399: { quality: "1080p Full HD", dimensions: "1920×1080", format: "AV1 Video", type: "video", combined: false },
  398: { quality: "720p HD", dimensions: "1280×720", format: "AV1 Video", type: "video", combined: false },
  397: { quality: "480p", dimensions: "854×480", format: "AV1 Video", type: "video", combined: false },
  140: { quality: "Audio", dimensions: "128 kbps Stereo", format: "M4A Audio", type: "audio", combined: false },
  251: { quality: "Audio", dimensions: "160 kbps Stereo", format: "Opus Audio", type: "audio", combined: false },
  250: { quality: "Audio", dimensions: "70 kbps Stereo", format: "Opus Audio", type: "audio", combined: false },
  249: { quality: "Audio", dimensions: "50 kbps Stereo", format: "Opus Audio", type: "audio", combined: false }
};

// Context Menus
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "macdl-download-link",
    title: "Download with FETCHDECK",
    contexts: ["link", "video", "audio", "image"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const targetUrl = info.linkUrl || info.srcUrl;
  if (!targetUrl || targetUrl.startsWith("blob:") || targetUrl.startsWith("data:")) {
    return;
  }

  const payload = {
    url: targetUrl,
    filename: targetUrl.split("/").pop().split("?")[0] || "download",
    referer: tab?.url || "",
    userAgent: navigator.userAgent
  };

  sendDownloadToApp(payload);
});

// YouTube Direct Resolver: Queries FETCHDECK daemon or InnerTube client
async function resolveYouTubeStreams(videoId, pageUrl = "") {
  let isDaemonOnline = false;

  // Attempt 1: Query FETCHDECK native daemon if active (best accuracy with yt-dlp + Node)
  try {
    const daemonRes = await fetch("http://127.0.0.1:45678/api/resolve", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ videoId: videoId || "", url: pageUrl || "" })
    });
    if (daemonRes.ok) {
      isDaemonOnline = true;
      const daemonData = await daemonRes.json();
      if (daemonData && daemonData.streams && daemonData.streams.length > 0) {
        return { streams: daemonData.streams, daemonOnline: true };
      }
    }
  } catch (e) {
    // Daemon offline, fall through to browser-side fallbacks
  }

  if (!videoId) return { streams: [], daemonOnline: isDaemonOnline };

  // Attempt 2: Direct InnerTube query via TVHTML5 client
  const tvClients = [
    {
      clientName: "TVHTML5",
      clientVersion: "7.20240901.12.00"
    },
    {
      clientName: "ANDROID",
      clientVersion: "19.29.35",
      androidSdkVersion: 34
    },
    {
      clientName: "IOS",
      clientVersion: "19.29.1",
      deviceModel: "iPhone16,2",
      osName: "iOS",
      osVersion: "17.5.1.21F90"
    }
  ];

  for (const clientConfig of tvClients) {
    try {
      const endpoint = "https://www.youtube.com/youtubei/v1/player";
      const body = {
        context: {
          client: {
            ...clientConfig,
            hl: "en",
            gl: "US"
          }
        },
        videoId: videoId
      };

      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      });

      if (!res.ok) continue;
      const data = await res.json();
      const streamingData = data.streamingData || {};
      const formats = streamingData.formats || [];
      const adaptive = streamingData.adaptiveFormats || [];
      if (formats.length === 0 && adaptive.length === 0) continue;

      const results = [];
      const seenQualities = new Set();

      let bestAudio = null;
      for (const f of adaptive) {
        if (f.url && f.mimeType && f.mimeType.includes("audio/")) {
          if (!bestAudio || f.mimeType.includes("audio/mp4")) {
            bestAudio = f;
            if (f.mimeType.includes("audio/mp4")) break;
          }
        }
      }

      const formatSize = (bytes) => {
        if (!bytes || bytes <= 0) return "Direct Stream";
        const mb = (bytes / (1024 * 1024)).toFixed(1);
        return `${mb} MB`;
      };

      // 1. Progressive muxed formats (itag 22: 720p, itag 18: 360p)
      for (const f of formats) {
        if (f.url) {
          const itag = f.itag || 0;
          const q = f.qualityLabel || (itag === 22 ? "720p" : "360p");
          const shortQ = q.replace(/60fps/gi, "").replace(/50fps/gi, "").trim();
          if (seenQualities.has(shortQ)) continue;
          seenQualities.add(shortQ);

          const w = f.width || (shortQ === "720p" ? 1280 : 640);
          const h = f.height || (shortQ === "720p" ? 720 : 360);
          const size = f.contentLength ? parseInt(f.contentLength, 10) : 0;

          results.push({
            url: f.url,
            audioUrl: null,
            label: `${shortQ} HD`,
            quality: shortQ,
            dimensions: `${w}×${h}`,
            format: "MP4 Video",
            type: "video",
            combined: true,
            size: size,
            formattedSize: formatSize(size),
            itag: itag
          });
        }
      }

      // 2. Adaptive video formats
      for (const f of adaptive) {
        if (f.url && f.mimeType && f.mimeType.includes("video/")) {
          const height = f.height || 0;
          const width = f.width || 0;
          const fps = f.fps || 30;
          if (height < 360) continue;

          const qualityKey = `${height}p`;
          if (seenQualities.has(qualityKey)) continue;
          seenQualities.add(qualityKey);

          const label = height >= 1080 ? `${height}p Full HD` : (height >= 720 ? `${height}p HD` : `${height}p SD`);
          const dim = width > 0 && height > 0 ? `${width}×${height} (${fps}fps)` : `${height}p`;
          const vSize = f.contentLength ? parseInt(f.contentLength, 10) : 0;
          const aSize = bestAudio && bestAudio.contentLength ? parseInt(bestAudio.contentLength, 10) : 0;
          const totalSize = vSize + aSize;

          results.push({
            url: f.url,
            audioUrl: bestAudio ? bestAudio.url : null,
            label: label,
            quality: qualityKey,
            dimensions: dim,
            format: f.mimeType.includes("mp4") ? "MP4 Video" : "WebM Video",
            type: "video",
            combined: false,
            size: totalSize,
            formattedSize: formatSize(totalSize),
            itag: f.itag || 0
          });
        }
      }

      // 3. Audio format (M4A Track)
      if (bestAudio && bestAudio.url) {
        const aSize = bestAudio.contentLength ? parseInt(bestAudio.contentLength, 10) : 0;
        results.push({
          url: bestAudio.url,
          audioUrl: null,
          label: "Audio Track (M4A)",
          quality: "Audio",
          dimensions: "128 kbps Stereo",
          format: "M4A Audio",
          type: "audio",
          combined: false,
          size: aSize,
          formattedSize: formatSize(aSize),
          itag: bestAudio.itag || 140
        });
      }

      // Sort: 1080p first, then 720p, 480p, 360p, then audio
      results.sort((a, b) => {
        if (a.type === "video" && b.type === "audio") return -1;
        if (a.type === "audio" && b.type === "video") return 1;
        const getP = (str) => parseInt((str || "").replace(/[^\d]/g, ""), 10) || 0;
        return getP(b.quality) - getP(a.quality);
      });

      if (results.length > 0) {
        return { streams: results, daemonOnline: isDaemonOnline };
      }
    } catch (err) {}
  }

  return { streams: [], daemonOnline: isDaemonOnline };
}

// Sniffer URL filter with IDM Master Stream Reconstruction
function parseMediaUrl(url, contentType = "", contentLength = 0) {
  if (!url || url.startsWith("blob:") || url.startsWith("data:")) return null;

  // Case 1: YouTube Google Video Playback
  if (url.includes("googlevideo.com/videoplayback")) {
    try {
      const urlObj = new URL(url);
      // Only skip tiny init segment stubs (e.g. range=0-31 or 0-100)
      const range = urlObj.searchParams.get("range") || "";
      if (range === "0-31" || range === "0-100") return null;

      const itagStr = urlObj.searchParams.get("itag");
      const itag = itagStr ? parseInt(itagStr, 10) : 0;
      if (!itag || !YOUTUBE_ITAGS[itag]) return null;

      const info = YOUTUBE_ITAGS[itag];
      const clen = urlObj.searchParams.get("clen");
      const size = clen ? parseInt(clen, 10) : contentLength;

      // IDM Master Stream Reconstruction: Remove streaming playback chunk hints (rn, sq, rbuf, range)
      // Since these are not in sparams, the cryptographic signature remains 100% valid!
      const cleanUrlObj = new URL(url);
      cleanUrlObj.searchParams.delete("range");
      cleanUrlObj.searchParams.delete("rn");
      cleanUrlObj.searchParams.delete("sq");
      cleanUrlObj.searchParams.delete("rbuf");
      const cleanMasterUrl = cleanUrlObj.toString();

      const formatSize = (bytes) => {
        if (!bytes || bytes <= 0) return "Direct Stream";
        const mb = (bytes / (1024 * 1024)).toFixed(1);
        return `${mb} MB`;
      };

      return {
        url: cleanMasterUrl,
        originalUrl: url,
        label: `YouTube ${info.quality} ${info.format}`,
        quality: info.quality,
        dimensions: info.dimensions || info.quality,
        format: info.format,
        type: info.type,
        combined: info.combined,
        size: size,
        formattedSize: formatSize(size),
        contentType: contentType || (info.type === "audio" ? "audio/mp4" : "video/mp4"),
        itag: itag,
        timestamp: Date.now()
      };
    } catch (e) {
      return null;
    }
  }

  // Case 2: HLS Stream (.m3u8)
  if (url.includes(".m3u8") || contentType.includes("mpegurl")) {
    return {
      url: url,
      originalUrl: url,
      label: "HLS Video Stream (.m3u8)",
      quality: "HLS Stream",
      dimensions: "Adaptive HLS",
      format: "HLS Stream",
      type: "video",
      combined: true,
      size: contentLength,
      contentType: contentType,
      timestamp: Date.now()
    };
  }

  // Case 3: MPEG-DASH (.mpd)
  if (url.includes(".mpd") || contentType.includes("dash+xml")) {
    return {
      url: url,
      originalUrl: url,
      label: "DASH Manifest (.mpd)",
      quality: "DASH Stream",
      dimensions: "Adaptive DASH",
      format: "DASH Stream",
      type: "video",
      combined: false,
      size: contentLength,
      contentType: contentType,
      timestamp: Date.now()
    };
  }

  // Case 4: Standard Video Files
  if (contentType.startsWith("video/") || url.match(/\.(mp4|webm|mkv|mov|avi|flv|m4v)(\?|$)/i)) {
    const ext = url.split("?")[0].split(".").pop().toUpperCase();
    return {
      url: url,
      originalUrl: url,
      label: `Video (${ext})`,
      quality: ext,
      dimensions: `${ext} Video`,
      format: `${ext} Video`,
      type: "video",
      combined: true,
      size: contentLength,
      contentType: contentType,
      timestamp: Date.now()
    };
  }

  // Case 5: Standard Audio Files
  if (contentType.startsWith("audio/") || url.match(/\.(mp3|m4a|aac|wav|ogg|flac)(\?|$)/i)) {
    const ext = url.split("?")[0].split(".").pop().toUpperCase();
    return {
      url: url,
      originalUrl: url,
      label: `Audio (${ext})`,
      quality: ext,
      dimensions: `${ext} Audio`,
      format: `${ext} Audio`,
      type: "audio",
      combined: true,
      size: contentLength,
      contentType: contentType,
      timestamp: Date.now()
    };
  }

  return null;
}

function registerMedia(tabId, mediaItem) {
  if (tabId < 0 || !mediaItem || !mediaItem.url) return;

  if (!tabMediaMap.has(tabId)) {
    tabMediaMap.set(tabId, []);
  }
  const list = tabMediaMap.get(tabId);

  // Check if identical clean URL or itag already registered
  const existingIndex = list.findIndex((item) => item.url === mediaItem.url || (item.itag && item.itag === mediaItem.itag));
  if (existingIndex >= 0) {
    if (mediaItem.size && !list[existingIndex].size) {
      list[existingIndex].size = mediaItem.size;
    }
    return;
  }

  if (mediaItem.combined) {
    list.unshift(mediaItem);
  } else {
    list.push(mediaItem);
  }

  if (list.length > 50) {
    list.pop();
  }

  // Automatic audio pairing for adaptive YouTube streams
  const bestAudio = list.find((item) => item.type === "audio");
  if (bestAudio) {
    for (const item of list) {
      if (item.type === "video" && !item.combined && !item.audioUrl) {
        item.audioUrl = bestAudio.url;
      }
    }
  }

  chrome.action.setBadgeText({ tabId, text: String(list.length) });
  chrome.action.setBadgeBackgroundColor({ tabId, color: "#007aff" });
}

// Sniff 1: onBeforeRequest
chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    if (details.tabId < 0) return;
    const url = details.url;

    if (
      url.includes(".m3u8") ||
      url.includes(".mpd") ||
      url.match(/\.(mp4|webm|m4s|m4a|mp3|ts)(\?|$)/i) ||
      url.includes("googlevideo.com/videoplayback") ||
      url.includes("mime=video") ||
      url.includes("mime=audio")
    ) {
      const parsed = parseMediaUrl(url);
      if (parsed) {
        registerMedia(details.tabId, parsed);
      }
    }
  },
  { urls: ["<all_urls>"] }
);

// Sniff 2: onResponseStarted
chrome.webRequest.onResponseStarted.addListener(
  (details) => {
    if (details.tabId < 0) return;

    const headers = details.responseHeaders || [];
    let contentType = "";
    let contentLength = 0;

    for (const h of headers) {
      const name = h.name.toLowerCase();
      if (name === "content-type") contentType = h.value.toLowerCase();
      if (name === "content-length") contentLength = parseInt(h.value, 10) || 0;
    }

    if (
      contentType.startsWith("video/") ||
      contentType.startsWith("audio/") ||
      contentType.includes("mpegurl") ||
      contentType.includes("dash+xml")
    ) {
      const parsed = parseMediaUrl(details.url, contentType, contentLength);
      if (parsed) {
        registerMedia(details.tabId, parsed);
      }
    }
  },
  { urls: ["<all_urls>"] },
  ["responseHeaders"]
);

// Clear tab cache on navigation
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") {
    tabMediaMap.delete(tabId);
    chrome.action.setBadgeText({ tabId, text: "" });
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  tabMediaMap.delete(tabId);
});

// Message Dispatcher
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "resolve_youtube_formats" || request.action === "resolve_youtube_streams") {
    const tabId = sender.tab?.id;
    const sniffed = tabId ? tabMediaMap.get(tabId) || [] : [];

    resolveYouTubeStreams(request.videoId, request.url).then((resData) => {
      const resStreams = (resData && resData.streams) || [];
      const daemonOnline = (resData && resData.daemonOnline) || false;
      if (resStreams && resStreams.length > 0) {
        sendResponse({ success: true, streams: resStreams, daemonOnline: daemonOnline });
        return;
      }
      // Fallback: sniffed streams with strict deduplication
      const deduplicated = [];
      const seen = new Set();
      for (const s of sniffed) {
        const k = (s.quality || "").toLowerCase().replace(/[^0-9a-z]/g, "");
        if (!seen.has(k)) {
          seen.add(k);
          deduplicated.push(s);
        }
      }
      sendResponse({ success: true, streams: deduplicated, daemonOnline: daemonOnline });
    });
    return true;
  }

  if (request.action === "send_to_app") {
    sendDownloadToApp(request.payload)
      .then((res) => sendResponse({ success: true, data: res }))
      .catch((err) => sendResponse({ success: false, error: err.message }));
    return true;
  }

  if (request.action === "download_in_browser") {
    chrome.downloads.download(
      {
        url: request.payload.url,
        filename: request.payload.filename || "download.mp4",
        saveAs: true
      },
      (downloadId) => {
        if (chrome.runtime.lastError) {
          sendResponse({ success: false, error: chrome.runtime.lastError.message });
        } else {
          sendResponse({ success: true, downloadId });
        }
      }
    );
    return true;
  }

  if (request.action === "get_tab_media") {
    const tabId = request.tabId || sender.tab?.id;
    const media = tabId ? tabMediaMap.get(tabId) || [] : [];
    sendResponse({ media });
    return false;
  }

  if (request.action === "register_client_media") {
    const tabId = sender.tab?.id;
    if (tabId && request.mediaList) {
      for (const m of request.mediaList) {
        registerMedia(tabId, m);
      }
    }
    sendResponse({ success: true });
    return false;
  }

  if (request.action === "check_status") {
    fetch(STATUS_ENDPOINT)
      .then((r) => r.json())
      .then((data) => sendResponse({ online: true, data }))
      .catch(() => sendResponse({ online: false }));
    return true;
  }
});

async function sendDownloadToApp(payload) {
  if (!payload.url || payload.url.startsWith("blob:") || payload.url.startsWith("data:")) {
    throw new Error("Invalid or unsupported stream URL. Blob URLs cannot be downloaded directly.");
  }

  // Forward Chrome YouTube session cookies
  try {
    const cookies = await chrome.cookies.getAll({ url: "https://www.youtube.com" });
    if (cookies && cookies.length > 0) {
      payload.cookie = cookies.map((c) => `${c.name}=${c.value}`).join("; ");
    }
  } catch (e) {}

  const response = await fetch(API_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`HTTP ${response.status}: ${errText}`);
  }
  return await response.json();
}
