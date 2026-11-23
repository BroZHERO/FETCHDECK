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
    if (cachedVideoDetails && cachedVideoDetails.videoId) return cachedVideoDetails.videoId;
    const meta = document.querySelector('meta[itemprop="videoId"]');
    if (meta && meta.content) return meta.content;
    return null;
  }

  function getQualityBadgeClass(q) {
    const lower = (q || "").toLowerCase();
    if (lower.includes("2160") || lower.includes("4k") || lower.includes("1440") || lower.includes("1080")) return "macdl-badge-1080p";
    if (lower.includes("720")) return "macdl-badge-720p";
    if (lower.includes("480")) return "macdl-badge-480p";
    if (lower.includes("360") || lower.includes("240")) return "macdl-badge-360p";
    if (lower.includes("suno")) return "macdl-badge-suno";
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
      return (
        url.includes("sig=") ||
        url.includes("signature=") ||
        url.includes("lsig=") ||
        url.includes("expire=") ||
        url.includes("id=")
      );
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

  let activeFloatingPill = null;
  let currentAudioItem = null;

  function extractSunoMetadata(audioUrl) {
    const uuidMatch = audioUrl.match(/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/);
    const uuid = uuidMatch ? uuidMatch[1] : null;

    let title = "";
    let artist = "";
    let imageUrl = "";

    if (uuid) {
      // 1. Search for link containing this UUID
      const link = document.querySelector(`a[href*="${uuid}"]`);
      if (link) {
        title = link.innerText.trim();
        const card = link.closest('[data-testid*="song"], [data-testid*="track"], div[class*="row"], div[class*="card"], div[class*="item"]') || link.parentElement?.parentElement;
        if (card) {
          const img = card.querySelector("img");
          if (img && img.src && !img.src.includes("avatar")) imageUrl = img.src;
          const artistEl = card.querySelector('a[href*="/@"], span[class*="creator"], span[class*="user"], div[class*="user"]');
          if (artistEl) artist = artistEl.innerText.trim();
        }
      }
    }

    // 2. Check bottom player bar
    if (!title) {
      const playerBar = document.querySelector('footer, [aria-label*="Player"], [data-testid*="player"], [class*="player-bar"], [class*="PlayerBar"]');
      if (playerBar) {
        const titleEl = playerBar.querySelector('a[href*="/song/"], [class*="title"], h3, h4, span[class*="font-bold"], div[class*="font-semibold"]');
        if (titleEl) title = titleEl.innerText.trim();
        const img = playerBar.querySelector("img");
        if (img && img.src) imageUrl = img.src;
        const artistEl = playerBar.querySelector('a[href*="/@"], [class*="creator"]');
        if (artistEl) artist = artistEl.innerText.trim();
      }
    }

    // 3. Check document.title (e.g., "Song Title by @artist | Suno" or "Song Title | Suno")
    if (!title && document.title) {
      let clean = document.title.replace(/\s*\|\s*Suno.*$/i, "").replace(/\s*-\s*Suno.*$/i, "").trim();
      if (clean.includes(" by @")) {
        const parts = clean.split(" by @");
        title = parts[0].trim();
        if (!artist) artist = "@" + parts[1].trim();
      } else if (clean && clean.toLowerCase() !== "suno") {
        title = clean;
      }
    }

    if (!title && uuid) {
      title = `Suno Track ${uuid.substring(0, 8)}`;
    }

    return {
      uuid,
      title: title || "Suno Track",
      artist: artist || "Suno AI",
      imageUrl: imageUrl || ""
    };
  }

  function extractGenericAudioMetadata(mediaElement, audioUrl) {
    let title = mediaElement.getAttribute("title") || mediaElement.getAttribute("aria-label");
    if (!title) {
      const parentWithTitle = mediaElement.closest("[title], [aria-label]");
      if (parentWithTitle) title = parentWithTitle.getAttribute("title") || parentWithTitle.getAttribute("aria-label");
    }
    if (!title && document.title) {
      title = document.title.replace(/[\\/:*?"<>|]/g, "_").trim();
    }
    if (!title) {
      const fn = audioUrl.split("?")[0].split("/").pop();
      if (fn) title = fn.replace(/\.[a-z0-9]+$/i, "");
    }
    return {
      title: title || "Audio Track",
      artist: window.location.hostname
    };
  }

  function handleAudioSource(mediaElement, src) {
    if (!src || src.startsWith("blob:") || src.startsWith("data:") || !src.startsWith("http")) return;

    const isSuno = window.location.hostname.includes("suno.com") || window.location.hostname.includes("suno.ai") || src.includes(".suno.ai") || src.includes("audiopipe");
    let meta = null;
    if (isSuno) {
      meta = extractSunoMetadata(src);
      // Register with background service worker
      chrome.runtime.sendMessage({
        action: "register_suno_metadata",
        metadata: {
          uuid: meta.uuid,
          title: meta.title,
          artist: meta.artist,
          audioUrl: src,
          imageUrl: meta.imageUrl
        }
      });
    } else {
      meta = extractGenericAudioMetadata(mediaElement, src);
    }

    const extMatch = (src.split("?")[0].split(".").pop() || "mp3").toUpperCase();
    const audioItem = {
      url: src,
      audioUrl: null,
      label: isSuno ? `Suno AI: ${meta.title}` : `Audio: ${meta.title} (${extMatch})`,
      title: meta.title,
      artist: meta.artist,
      thumbnail: meta.imageUrl || null,
      quality: isSuno ? "320 kbps MP3" : extMatch,
      dimensions: isSuno ? "Suno Master" : `${extMatch} Audio`,
      format: isSuno ? "MP3 Audio" : `${extMatch} Audio`,
      type: "audio",
      category: "audio",
      combined: true,
      size: 0,
      formattedSize: "Direct Audio"
    };

    currentAudioItem = audioItem;

    // Register into background cache so popup picks it up immediately
    chrome.runtime.sendMessage({
      action: "register_client_media",
      mediaList: [audioItem]
    });

    // Render persistent floating audio pill
    renderFloatingAudioPill(audioItem);
  }

  function renderFloatingAudioPill(item) {
    if (activeFloatingPill) {
      activeFloatingPill.remove();
      activeFloatingPill = null;
    }

    const pill = document.createElement("div");
    pill.className = "macdl-audio-floating-pill";

    const thumbHtml = item.thumbnail
      ? `<img src="${escapeHtml(item.thumbnail)}" class="macdl-audio-thumb" alt="Cover"/>`
      : `<div class="macdl-audio-icon-wrap"><span class="macdl-audio-note">🎵</span></div>`;

    pill.innerHTML = `
      <div class="macdl-audio-pill-inner">
        ${thumbHtml}
        <div class="macdl-audio-info">
          <div class="macdl-audio-title" title="${escapeHtml(item.title || item.label)}">${escapeHtml(item.title || "Audio Track")}</div>
          <div class="macdl-audio-sub">${escapeHtml(item.artist ? `${item.artist} • ` : "")}${escapeHtml(item.quality || "MP3 Audio")}</div>
        </div>
        <div class="macdl-audio-actions">
          <button class="macdl-audio-btn-app" title="Send to FETCHDECK App">🚀 FetchDeck</button>
          <button class="macdl-audio-btn-browser" title="Download in Browser">⬇ Browser</button>
          <button class="macdl-audio-close" title="Dismiss">&times;</button>
        </div>
      </div>
    `;

    pill.querySelector(".macdl-audio-btn-app").addEventListener("click", (e) => {
      e.stopPropagation();
      dispatchDownload(item, pill.querySelector(".macdl-audio-btn-app"), false);
    });

    pill.querySelector(".macdl-audio-btn-browser").addEventListener("click", (e) => {
      e.stopPropagation();
      dispatchDownload(item, pill.querySelector(".macdl-audio-btn-browser"), true);
    });

    pill.querySelector(".macdl-audio-close").addEventListener("click", (e) => {
      e.stopPropagation();
      pill.remove();
      activeFloatingPill = null;
    });

    document.body.appendChild(pill);
    activeFloatingPill = pill;
  }

  function attachOverlay(mediaElement) {
    if (mediaElement.dataset.macdlAttached === "true") return;

    const isAudio = mediaElement.tagName.toLowerCase() === "audio";

    // For audio elements: hook playback listeners to capture audio stream & show floating pill
    if (isAudio) {
      mediaElement.dataset.macdlAttached = "true";
      const onAudioPlay = () => {
        const src = getDirectSource(mediaElement);
        if (src) handleAudioSource(mediaElement, src);
      };
      mediaElement.addEventListener("play", onAudioPlay);
      mediaElement.addEventListener("playing", onAudioPlay);
      mediaElement.addEventListener("loadedmetadata", onAudioPlay);
      const initialSrc = getDirectSource(mediaElement);
      if (initialSrc) handleAudioSource(mediaElement, initialSrc);

      // Only attach in-place overlay button if audio element is visibly rendered
      const rect = mediaElement.getBoundingClientRect();
      if (rect.width < 100 || rect.height < 24) return;
    } else {
      // For video elements: skip tiny icons or decorative videos
      const rect = mediaElement.getBoundingClientRect();
      if (rect.width < 120 && rect.height < 60) return;
      mediaElement.dataset.macdlAttached = "true";
    }

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

      // Request fresh streaming data from yt_main.js
      window.postMessage({ type: "MACDL_REQUEST_YT_DATA" }, "*");

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

      if (window.location.hostname.includes("youtube.com")) {
        window.postMessage({ type: "MACDL_REQUEST_YT_DATA" }, "*");
      }

      // Query universal resolver in background (supports YouTube, TikTok, Instagram, Twitter, Vimeo, and any video site)
      chrome.runtime.sendMessage(
        {
          action: "resolve_universal_media",
          url: window.location.href,
          videoId: getVideoId(),
          directSource: getDirectSource(mediaElement)
        },
        (res) => {
          let streams = (res && res.streams) || [];
          const daemonOnline = (res && res.daemonOnline) || false;
          if (!streams || streams.length === 0) {
            streams = parseAllStreams(cachedStreamingData, cachedCapturedStreams, (res && res.sniffed) || []);
          }
          renderDropdown(streams, container, button, daemonOnline);
        }
      );
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

  function renderDropdown(mediaList, container, triggerBtn, daemonOnline = true) {
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
      if (!daemonOnline) {
        emptyNotice.innerHTML = `
          <div class="macdl-offline-badge">● FETCHDECK App Offline</div>
          <div class="macdl-offline-desc">FETCHDECK is required to resolve and accelerate 4K, 1080p, and multi-chunk streams:</div>
          <a href="fetchdeck://open" class="macdl-btn-launch-app">🚀 Launch FETCHDECK App</a>
          <div class="macdl-offline-tip">Or press Play ▶ on the video for 1 second to sniff direct streams!</div>
        `;
      } else {
        emptyNotice.innerHTML = `
          <strong>No media stream detected yet.</strong><br>
          Please press Play ▶ on the video for 1 second, then click this button again!
        `;
      }
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

    const isAudio = item.type === "audio" || (item.format && item.format.toLowerCase().includes("audio"));
    const isSuno = item.url.includes(".suno.ai") || item.url.includes(".suno.com") || item.url.includes("audiopipe");

    let rawTitle = item.title || (cachedVideoDetails && cachedVideoDetails.title) || document.title || "media_download";
    rawTitle = rawTitle.replace(/ - YouTube$/, "").replace(/\s*\|\s*Suno.*$/i, "").replace(/[\\/:*?"<>|]/g, "_").trim();

    let ext = "mp4";
    if (isAudio || item.quality === "MP3" || isSuno) {
      if (item.url.includes(".mp3") || (item.format && item.format.includes("MP3")) || isSuno) {
        ext = "mp3";
      } else if (item.url.includes(".wav")) {
        ext = "wav";
      } else if (item.url.includes(".flac")) {
        ext = "flac";
      } else {
        ext = "m4a";
      }
    }

    const filename = isSuno
      ? `${rawTitle || "Suno_AI_Song"} - Suno AI.${ext}`
      : `${item.quality ? `[${item.quality}] ` : ""}${rawTitle}.${ext}`;

    const payload = {
      url: item.url,
      pageUrl: window.location.href,
      audioUrl: item.audioUrl || null,
      filename: filename,
      quality: item.quality || (isAudio ? "320 kbps MP3" : "HD"),
      dimensions: item.dimensions || "",
      formatId: item.formatId || null,
      category: isAudio || isSuno ? "audio" : "video",
      thumbnail: item.thumbnail || null,
      referer: window.location.href,
      userAgent: navigator.userAgent
    };

    if (inBrowser) {
      chrome.runtime.sendMessage({ action: "download_in_browser", payload }, (res) => {
        if (res && res.success) {
          showTemporaryFeedback(button, "✓ Downloading in Browser", "macdl-success");
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

    // Suno AI proactive scanner for currently playing song
    if (window.location.hostname.includes("suno.com") || window.location.hostname.includes("suno.ai")) {
      const audioEl = document.querySelector("audio");
      if (audioEl) {
        const src = getDirectSource(audioEl);
        if (src) handleAudioSource(audioEl, src);
      }
    }
  }

  let scanThrottle = null;
  function throttledScan() {
    if (scanThrottle) return;
    scanThrottle = setTimeout(() => {
      scanThrottle = null;
      scanMedia();
    }, 400);
  }

  scanMedia();

  const observer = new MutationObserver(() => {
    throttledScan();
  });
  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
  } else {
    document.addEventListener("DOMContentLoaded", () => {
      observer.observe(document.body, { childList: true, subtree: true });
    });
  }

  setTimeout(() => {
    window.postMessage({ type: "MACDL_REQUEST_YT_DATA" }, "*");
  }, 800);
})();
