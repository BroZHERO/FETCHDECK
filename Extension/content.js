(() => {
  if (window.__macdl_injected) return;
  window.__macdl_injected = true;

  let cachedStreamingData = null;
  let cachedCapturedStreams = [];
  let cachedVideoDetails = null;

  const YOUTUBE_ITAG_MAP = {
    18: { quality: "360p", dimensions: "640×360", format: "MP4 Video", combined: true, type: "video" },
    22: { quality: "720p", dimensions: "1280×720", format: "MP4 Video", combined: true, type: "video" },
    137: { quality: "1080p", dimensions: "1920×1080", format: "MP4 Video", combined: false, type: "video" },
    136: { quality: "720p", dimensions: "1280×720", format: "MP4 Video", combined: false, type: "video" },
    135: { quality: "480p", dimensions: "854×480", format: "MP4 Video", combined: false, type: "video" },
    134: { quality: "360p", dimensions: "640×360", format: "MP4 Video", combined: false, type: "video" },
    140: { quality: "Audio", dimensions: "128 kbps Stereo", format: "M4A Audio", combined: false, type: "audio" },
    251: { quality: "Audio", dimensions: "160 kbps Stereo", format: "Opus Audio", combined: false, type: "audio" }
  };

  // Listen for YouTube player data dispatched from yt_main.js
  window.addEventListener("message", (event) => {
    if (event.data && event.data.type === "MACDL_YT_PLAYER_DATA") {
      cachedStreamingData = event.data.streamingData;
      cachedCapturedStreams = event.data.capturedStreams || [];
      cachedVideoDetails = event.data.videoDetails;
    }
  });

  function getVideoId() {
    if (!window.location.hostname.includes("youtube.com")) return null;
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.has("v")) return urlParams.get("v");
    const shortsMatch = window.location.pathname.match(/\/shorts\/([a-zA-Z0-9_-]+)/);
    if (shortsMatch) return shortsMatch[1];
    const embedMatch = window.location.pathname.match(/\/embed\/([a-zA-Z0-9_-]+)/);
    if (embedMatch) return embedMatch[1];
    return null;
  }

  function getQualityBadgeClass(q) {
    const lower = (q || "").toLowerCase();
    if (lower.includes("2160") || lower.includes("4k") || lower.includes("1440") || lower.includes("1080")) return "macdl-badge-1080p";
    if (lower.includes("720")) return "macdl-badge-720p";
    if (lower.includes("480")) return "macdl-badge-480p";
    if (lower.includes("360") || lower.includes("240")) return "macdl-badge-360p";
    if (lower.includes("audio") || lower.includes("mp3")) return "macdl-badge-audio";
    return "macdl-badge-generic";
  }

  function getCleanQuality(q, height) {
    if (height && height > 0) return `${height}p`;
    if (!q) return "HD";
    let str = String(q).trim();
    str = str.replace(/60fps/gi, "").replace(/50fps/gi, "").trim();
    if (/^\d+p?$/i.test(str)) {
      return str.endsWith("p") ? str : `${str}p`;
    }
    return str;
  }

  function formatSize(bytes) {
    if (!bytes || bytes <= 0) return "Direct Stream";
    const mb = (bytes / (1024 * 1024)).toFixed(1);
    return `${mb} MB`;
  }

  function isSignedUrl(url) {
    if (!url) return false;
    if (url.includes("googlevideo.com")) {
      return url.includes("sig=") || url.includes("signature=");
    }
    return true;
  }

  function parseAllStreams(streamingData, capturedStreams, sniffedMedia) {
    const list = [];
    const seenQualities = new Set();
    const allCaptured = [...(capturedStreams || []), ...(sniffedMedia || [])];

    let bestAudioUrl = null;
    let bestAudioSize = 0;

    for (const c of allCaptured) {
      if ((c.itag === 140 || c.itag === 251 || c.type === "audio") && isSignedUrl(c.url)) {
        bestAudioUrl = c.url;
        bestAudioSize = c.size || 0;
        break;
      }
    }

    const adaptive = (streamingData && streamingData.adaptiveFormats) || [];
    if (!bestAudioUrl) {
      for (const f of adaptive) {
        if (f.url && f.mimeType && f.mimeType.includes("audio/") && isSignedUrl(f.url)) {
          bestAudioUrl = f.url;
          bestAudioSize = parseInt(f.contentLength, 10) || 0;
          if (f.mimeType.includes("audio/mp4")) break;
        }
      }
    }

    // 1. Process Progressive muxed formats from player response (itag 22: 720p, itag 18: 360p)
    const formats = (streamingData && streamingData.formats) || [];
    for (const f of formats) {
      if (!f.url || !isSignedUrl(f.url)) continue;
      const q = getCleanQuality(f.qualityLabel || f.quality, f.height);
      const qKey = q.toLowerCase().replace(/[^0-9a-z]/g, "");
      if (seenQualities.has(qKey)) continue;
      seenQualities.add(qKey);

      const w = f.width || (q === "720p" ? 1280 : 640);
      const h = f.height || (q === "720p" ? 720 : 360);
      const size = parseInt(f.contentLength, 10) || 0;

      list.push({
        url: f.url,
        audioUrl: null,
        label: `YouTube ${q} (Video + Audio)`,
        quality: q,
        dimensions: `${w}×${h}`,
        format: "MP4 Video",
        type: "video",
        combined: true,
        size: size,
        formattedSize: formatSize(size),
        itag: f.itag
      });
    }

    // 2. Process Adaptive video formats (1080p, 720p, 480p, 360p)
    for (const f of adaptive) {
      if (!f.url || !isSignedUrl(f.url)) continue;
      if (!f.mimeType || !f.mimeType.includes("video/")) continue;

      const height = f.height || 0;
      if (height < 360) continue;
      const q = `${height}p`;
      const qKey = q.toLowerCase().replace(/[^0-9a-z]/g, "");
      if (seenQualities.has(qKey)) continue;
      seenQualities.add(qKey);

      const width = f.width || 0;
      const fps = f.fps || 30;
      const label = height >= 1080 ? `YouTube 1080p Full HD` : (height >= 720 ? `YouTube 720p HD` : `YouTube ${height}p SD`);
      const dim = width > 0 && height > 0 ? `${width}×${height} (${fps}fps)` : `${height}p`;
      const vSize = parseInt(f.contentLength, 10) || 0;
      const totalSize = vSize + bestAudioSize;

      list.push({
        url: f.url,
        audioUrl: bestAudioUrl,
        label: label,
        quality: q,
        dimensions: dim,
        format: f.mimeType.includes("mp4") ? "MP4 Video" : "WebM Video",
        type: "video",
        combined: false,
        size: totalSize,
        formattedSize: formatSize(totalSize),
        itag: f.itag
      });
    }

    // 3. Process Captured & Sniffed Media
    for (const item of allCaptured) {
      if (!isSignedUrl(item.url)) continue;
      const itag = item.itag;
      const itagInfo = itag ? YOUTUBE_ITAG_MAP[itag] : null;

      const q = itagInfo ? itagInfo.quality : getCleanQuality(item.quality, 0);
      const qKey = q.toLowerCase().replace(/[^0-9a-z]/g, "");
      if (seenQualities.has(qKey)) continue;
      seenQualities.add(qKey);

      const isAudio = (itagInfo && itagInfo.type === "audio") || item.type === "audio";
      const combined = (itagInfo && itagInfo.combined) || item.combined || false;
      const label = itagInfo
        ? (combined ? `YouTube ${q} (Video + Audio)` : (isAudio ? "Audio Track (M4A)" : `YouTube ${q} Full HD`))
        : (item.label || `${q} Video`);
      const dim = itagInfo ? itagInfo.dimensions : (item.dimensions || q);

      list.push({
        url: item.url,
        audioUrl: combined || isAudio ? null : bestAudioUrl,
        label: label,
        quality: q,
        dimensions: dim,
        format: itagInfo ? itagInfo.format : (isAudio ? "M4A Audio" : "MP4 Video"),
        type: isAudio ? "audio" : "video",
        combined: combined,
        size: item.size || 0,
        formattedSize: formatSize(item.size || 0)
      });
    }

    // 4. Standalone Audio option
    if (bestAudioUrl && !seenQualities.has("audio")) {
      seenQualities.add("audio");
      list.push({
        url: bestAudioUrl,
        audioUrl: null,
        label: "Audio Track (M4A)",
        quality: "Audio",
        dimensions: "128 kbps Stereo",
        format: "M4A Audio",
        type: "audio",
        combined: false,
        size: bestAudioSize,
        formattedSize: formatSize(bestAudioSize),
        itag: 140
      });
    }

    list.sort((a, b) => {
      if (a.type === "video" && b.type === "audio") return -1;
      if (a.type === "audio" && b.type === "video") return 1;
      const getP = (str) => parseInt((str || "").replace(/[^\d]/g, ""), 10) || 0;
      return getP(b.quality) - getP(a.quality);
    });

    return list;
  }

  function attachOverlay(mediaElement) {
    if (mediaElement.dataset.macdlAttached === "true") return;

    const rect = mediaElement.getBoundingClientRect();
    if (rect.width < 120 && rect.height < 60) return;

    mediaElement.dataset.macdlAttached = "true";

    let parent = mediaElement.parentElement;
    if (!parent) return;

    const computedPos = window.getComputedStyle(parent).position;
    if (computedPos === "static") {
      parent.style.position = "relative";
    }

    const container = document.createElement("div");
    container.className = "macdl-overlay-container";

    const defaultBtnHtml = `
      <svg class="macdl-icon" viewBox="0 0 24 24">
        <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/>
      </svg>
      <span class="macdl-btn-label">FetchDeck</span>
    `;

    const button = document.createElement("button");
    button.className = "macdl-download-btn";
    button.innerHTML = defaultBtnHtml;

    button.addEventListener("click", (e) => {
      e.stopPropagation();
      e.preventDefault();

      const existing = container.querySelector(".macdl-dropdown");
      if (existing) {
        existing.remove();
        button.classList.remove("macdl-active");
        return;
      }

      button.classList.add("macdl-active");

      // Show immediate loading popover with spinner
      const loadingDropdown = document.createElement("div");
      loadingDropdown.className = "macdl-dropdown";
      loadingDropdown.innerHTML = `
        <div class="macdl-dropdown-header">
          <span>SELECT RESOLUTION</span>
          <button class="macdl-close-btn">&times;</button>
        </div>
        <div class="macdl-loading-box">
          <div class="macdl-loading-spinner"></div>
          <span>Discovering available resolutions...</span>
        </div>
      `;
      loadingDropdown.querySelector(".macdl-close-btn").addEventListener("click", (evt) => {
        evt.stopPropagation();
        loadingDropdown.remove();
        button.classList.remove("macdl-active");
      });
      container.appendChild(loadingDropdown);

      const isYouTube = window.location.hostname.includes("youtube.com");

      if (isYouTube) {
        // Query background daemon resolver with full yt-dlp challenge solver
        chrome.runtime.sendMessage(
          {
            action: "resolve_youtube_formats",
            url: window.location.href,
            videoId: getVideoId()
          },
          (res) => {
            let streams = (res && res.streams) || [];
            if (!streams || streams.length === 0) {
              streams = parseAllStreams(cachedStreamingData, cachedCapturedStreams, []);
            }
            renderDropdown(streams, container, button);
          }
        );
      } else {
        // Non-YouTube video site: query background sniffer
        chrome.runtime.sendMessage({ action: "get_tab_media" }, (tabRes) => {
          const sniffedMedia = (tabRes && tabRes.media) || [];
          const directSource = getDirectSource(mediaElement);
          if (directSource && !sniffedMedia.some((m) => m.url === directSource)) {
            sniffedMedia.unshift({
              url: directSource,
              label: "Direct Video Stream",
              quality: "Source",
              dimensions: "Original",
              format: "Direct Media",
              size: 0,
              type: mediaElement.tagName.toLowerCase() === "video" ? "video" : "audio",
              combined: true
            });
          }
          const streams = parseAllStreams(cachedStreamingData, cachedCapturedStreams, sniffedMedia);
          renderDropdown(streams, container, button);
        });
      }
    });

    container.appendChild(button);
    parent.appendChild(container);
  }

  function getDirectSource(mediaElement) {
    const isValid = (src) => src && !src.startsWith("blob:") && !src.startsWith("data:") && src.startsWith("http");
    if (isValid(mediaElement.currentSrc)) return mediaElement.currentSrc;
    if (isValid(mediaElement.src)) return mediaElement.src;
    const sourceTag = mediaElement.querySelector("source[src]");
    if (sourceTag && isValid(sourceTag.src)) return sourceTag.src;
    return null;
  }

  function renderDropdown(mediaList, container, triggerBtn) {
    const existing = container.querySelector(".macdl-dropdown");
    if (existing) existing.remove();

    const dd = document.createElement("div");
    dd.className = "macdl-dropdown";

    const header = document.createElement("div");
    header.className = "macdl-dropdown-header";
    header.innerHTML = `
      <span>SELECT RESOLUTION (${mediaList.length})</span>
      <button class="macdl-close-btn">&times;</button>
    `;
    header.querySelector(".macdl-close-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      dd.remove();
      triggerBtn.classList.remove("macdl-active");
    });
    dd.appendChild(header);

    triggerBtn.classList.add("macdl-active");

    if (mediaList.length === 0) {
      const emptyNotice = document.createElement("div");
      emptyNotice.className = "macdl-empty-notice";
      emptyNotice.innerHTML = `
        <strong>No media stream detected yet.</strong><br>
        Please start the video or check that FETCHDECK is running!
      `;
      dd.appendChild(emptyNotice);
    } else {
      const listEl = document.createElement("div");
      listEl.className = "macdl-dropdown-list";

      mediaList.forEach((item) => {
        const itemRow = document.createElement("div");
        itemRow.className = "macdl-dropdown-item";

        const q = item.quality || "HD";
        const badgeClass = getQualityBadgeClass(q);
        const dimensions = item.dimensions || (q === "1080p" ? "1920×1080" : (q === "720p" ? "1280×720" : (q === "480p" ? "854×480" : (q === "360p" ? "640×360" : "Stereo"))));
        const format = item.format || (item.type === "audio" ? "M4A Audio" : "MP4 Video");
        const sizeStr = item.formattedSize || (item.size > 0 ? `${(item.size / (1024 * 1024)).toFixed(1)} MB` : "");

        const audioNotice = item.combined
          ? `<span class="macdl-meta-pill macdl-pill-green">Full Video + Audio</span>`
          : (item.type === "audio" ? `<span class="macdl-meta-pill macdl-pill-blue">Audio Track</span>` : `<span class="macdl-meta-pill macdl-pill-blue">Video + Audio Muxed</span>`);

        itemRow.innerHTML = `
          <div class="macdl-item-left" title="${escapeHtml(item.url)}">
            <div class="macdl-item-title-row">
              <span class="macdl-res-badge ${badgeClass}">${escapeHtml(q)}</span>
              <span class="macdl-title-text">${escapeHtml(item.label || "Stream")}</span>
            </div>
            <div class="macdl-item-meta-row">
              <span class="macdl-meta-pill">${escapeHtml(dimensions)}</span>
              <span class="macdl-meta-pill">${escapeHtml(format)}</span>
              ${audioNotice}
              ${sizeStr ? `<span class="macdl-meta-size">• ${escapeHtml(sizeStr)}</span>` : ""}
            </div>
          </div>
          <div class="macdl-item-actions">
            <button class="macdl-btn-action macdl-btn-app" title="Accelerate with FETCHDECK">🚀 FetchDeck</button>
            <button class="macdl-btn-action macdl-btn-browser" title="Direct browser download">⬇ Browser</button>
          </div>
        `;

        itemRow.querySelector(".macdl-btn-app").addEventListener("click", (e) => {
          e.stopPropagation();
          e.preventDefault();
          dispatchDownload(item, triggerBtn, false);
          dd.remove();
          triggerBtn.classList.remove("macdl-active");
        });

        itemRow.querySelector(".macdl-btn-browser").addEventListener("click", (e) => {
          e.stopPropagation();
          e.preventDefault();
          dispatchDownload(item, triggerBtn, true);
          dd.remove();
          triggerBtn.classList.remove("macdl-active");
        });

        listEl.appendChild(itemRow);
      });

      dd.appendChild(listEl);
    }

    const dismissHandler = (e) => {
      if (!container.contains(e.target)) {
        dd.remove();
        triggerBtn.classList.remove("macdl-active");
        document.removeEventListener("click", dismissHandler);
      }
    };
    setTimeout(() => {
      document.addEventListener("click", dismissHandler);
    }, 10);

    container.appendChild(dd);
  }

  function dispatchDownload(item, button, inBrowser = false) {
    if (!item.url || item.url.startsWith("blob:") || item.url.startsWith("data:")) {
      showTemporaryFeedback(button, "Cannot download blob stream", "macdl-error");
      return;
    }

    let rawTitle = (cachedVideoDetails && cachedVideoDetails.title) || document.title || "media_download";
    rawTitle = rawTitle.replace(/ - YouTube$/, "").replace(/[\\/:*?"<>|]/g, "_").trim();

    const qTag = item.quality ? `[${item.quality}] ` : "";
    let ext = "mp4";
    if (item.quality === "MP3") {
      ext = "mp3";
    } else if (item.type === "audio") {
      ext = "m4a";
    }
    const filename = `${qTag}${rawTitle}.${ext}`;

    const payload = {
      url: item.url,
      pageUrl: window.location.href,
      audioUrl: item.audioUrl || null,
      filename: filename,
      quality: item.quality || "HD",
      dimensions: item.dimensions || "",
      formatId: item.formatId || null,
      referer: window.location.href,
      userAgent: navigator.userAgent
    };

    if (inBrowser) {
      chrome.runtime.sendMessage({ action: "download_in_browser", payload }, (res) => {
        if (res && res.success) {
          showTemporaryFeedback(button, "✓ Downloading in Chrome", "macdl-success");
        } else {
          showTemporaryFeedback(button, "Download Failed", "macdl-error");
        }
      });
      return;
    }

    chrome.runtime.sendMessage({ action: "send_to_app", payload }, (res) => {
      if (res && res.success) {
        showTemporaryFeedback(button, "✓ Sent to FETCHDECK", "macdl-success");
      } else {
        showTemporaryFeedback(button, "Start FETCHDECK App", "macdl-error");
      }
    });
  }

  function showTemporaryFeedback(button, text, className) {
    const labelSpan = button.querySelector(".macdl-btn-label") || button;
    const originalText = labelSpan.innerText;
    button.classList.add(className);
    labelSpan.innerText = text;
    setTimeout(() => {
      button.classList.remove(className);
      labelSpan.innerText = originalText;
    }, 2800);
  }

  function escapeHtml(str) {
    if (!str) return "";
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function scanMedia() {
    document.querySelectorAll("video, audio").forEach(attachOverlay);
  }

  scanMedia();

  const observer = new MutationObserver(() => {
    scanMedia();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  setTimeout(() => {
    window.postMessage({ type: "MACDL_REQUEST_YT_DATA" }, "*");
  }, 400);
  setTimeout(() => {
    window.postMessage({ type: "MACDL_REQUEST_YT_DATA" }, "*");
  }, 1200);
})();
