(() => {
  if (window.__macdl_suno_injected) return;
  window.__macdl_suno_injected = true;

  const capturedClips = new Map();
  const resolvedDownloadUrls = new Map();
  window.__macdl_resolvedUrls = resolvedDownloadUrls;
  window.__macdl_suno_bearer = null;

  // Helper to extract Clerk token or captured Bearer token
  async function getAuthToken() {
    try {
      if (window.Clerk && window.Clerk.session && typeof window.Clerk.session.getToken === "function") {
        const token = await window.Clerk.session.getToken();
        if (token) {
          window.__macdl_suno_bearer = token;
          return token;
        }
      }
    } catch (e) {}
    return window.__macdl_suno_bearer || null;
  }
  window.__macdl_getSunoToken = getAuthToken;

  // Resolve official Suno signed download URL for a clip
  async function resolveSunoDownloadUrl(clipId, format = "mp3") {
    if (!clipId || typeof clipId !== "string") return null;
    if (resolvedDownloadUrls.has(clipId)) {
      return resolvedDownloadUrls.get(clipId);
    }

    let token = await getAuthToken();
    const headers = {
      "Accept": "application/json, text/plain, */*"
    };
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    const apiHosts = [
      `https://studio-api.prod.suno.com/api/download/clip/${clipId}?format=${format}`,
      `https://studio-api-prod.suno.com/api/download/clip/${clipId}?format=${format}`
    ];

    for (const apiUrl of apiHosts) {
      for (let attempt = 0; attempt < 8; attempt++) {
        try {
          const res = await originalFetch(apiUrl, {
            method: "GET",
            headers: headers,
            credentials: "include"
          });

          if (res.status === 401 && !token) {
            token = await getAuthToken();
            if (token) {
              headers["Authorization"] = `Bearer ${token}`;
              continue;
            }
          }

          if (!res.ok) break;

          const data = await res.json();
          if (data && data.status === "ready" && data.download_url) {
            resolvedDownloadUrls.set(clipId, data.download_url);
            window.postMessage({
              type: "FETCHDECK_SUNO_DOWNLOAD_URL_READY",
              clipId: clipId,
              downloadUrl: data.download_url,
              authToken: token
            }, "*");
            return data.download_url;
          }

          if (data && data.status === "processing") {
            await new Promise((r) => setTimeout(r, 1000));
            continue;
          }
          break;
        } catch (e) {
          break;
        }
      }
      if (resolvedDownloadUrls.has(clipId)) break;
    }

    return resolvedDownloadUrls.get(clipId) || null;
  }
  window.__macdl_resolveSunoDownload = resolveSunoDownloadUrl;

  function extractClips(obj, list = []) {
    if (!obj || typeof obj !== "object") return list;

    if (obj.id && (obj.audio_url || obj.title || obj.metadata)) {
      let audioUrl = obj.audio_url || "";
      if (audioUrl.includes("forbidden") || !audioUrl) {
        // If forbidden or missing, check if already resolved
        audioUrl = resolvedDownloadUrls.get(obj.id) || "";
      }

      const item = {
        id: obj.id,
        title: obj.title || "Suno Track",
        audioUrl: audioUrl,
        imageUrl: obj.image_url || obj.image_large_url || "",
        duration: obj.duration || 0,
        artist: obj.display_name || obj.user_name || "Suno AI"
      };

      list.push(item);
      capturedClips.set(obj.id, item);
      if (obj.title) {
        capturedClips.set(obj.title.trim().toLowerCase(), item);
      }

      // Automatically initiate background resolution of real signed download URL
      if (!resolvedDownloadUrls.has(obj.id)) {
        setTimeout(() => {
          resolveSunoDownloadUrl(obj.id, "mp3").catch(() => {});
        }, 100);
      }
    }

    if (Array.isArray(obj)) {
      for (const el of obj) extractClips(el, list);
    } else {
      for (const k of Object.keys(obj)) {
        if (typeof obj[k] === "object") {
          extractClips(obj[k], list);
        }
      }
    }
    return list;
  }

  // 1. Intercept window.fetch to capture auth tokens & Suno API clip feeds
  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
    try {
      const url = typeof args[0] === "string" ? args[0] : (args[0] && args[0].url) || "";
      const headers = args[1]?.headers;
      let authHeader = null;
      if (headers) {
        if (typeof headers.get === "function") {
          authHeader = headers.get("Authorization") || headers.get("authorization");
        } else if (headers["Authorization"]) {
          authHeader = headers["Authorization"];
        } else if (headers["authorization"]) {
          authHeader = headers["authorization"];
        }
      }
      if (authHeader && authHeader.startsWith("Bearer ")) {
        window.__macdl_suno_bearer = authHeader.replace("Bearer ", "").trim();
      }
    } catch (e) {}

    const res = await originalFetch.apply(this, args);
    try {
      const url = typeof args[0] === "string" ? args[0] : (args[0] && args[0].url) || "";
      if (url.includes("suno.com") || url.includes("suno.ai")) {
        const clone = res.clone();
        clone.json().then((data) => {
          const clips = extractClips(data);
          if (clips.length > 0) {
            window.postMessage({
              type: "FETCHDECK_SUNO_TRACKS",
              tracks: clips
            }, "*");
          }
        }).catch(() => {});
      }
    } catch (e) {}
    return res;
  };

  // 2. Intercept XMLHttpRequest as fallback
  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this._macdlUrl = url;
    return origOpen.apply(this, [method, url, ...rest]);
  };
  XMLHttpRequest.prototype.send = function(...args) {
    this.addEventListener("load", function() {
      try {
        const url = this._macdlUrl || "";
        if (url.includes("suno.com") || url.includes("suno.ai")) {
          const data = JSON.parse(this.responseText);
          const clips = extractClips(data);
          if (clips.length > 0) {
            window.postMessage({
              type: "FETCHDECK_SUNO_TRACKS",
              tracks: clips
            }, "*");
          }
        }
      } catch (e) {}
    });
    return origSend.apply(this, args);
  };

  // 3. Hook HTMLMediaElement.prototype.play to signal audio playback immediately
  const origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    try {
      const currentSrc = this.currentSrc || this.src || "";
      window.postMessage({
        type: "FETCHDECK_AUDIO_PLAYING",
        src: currentSrc
      }, "*");
    } catch (e) {}
    return origPlay.apply(this, arguments);
  };

  // 4. Listen for URL resolution requests from content.js
  window.addEventListener("message", async (event) => {
    if (!event.data || typeof event.data !== "object") return;

    if (event.data.type === "FETCHDECK_RESOLVE_SUNO_URL" && event.data.clipId) {
      const clipId = event.data.clipId;
      const downloadUrl = await resolveSunoDownloadUrl(clipId, event.data.format || "mp3");
      const token = await getAuthToken();
      window.postMessage({
        type: "FETCHDECK_SUNO_URL_RESOLVED",
        requestId: event.data.requestId,
        clipId: clipId,
        downloadUrl: downloadUrl,
        authToken: token
      }, "*");
    }
  });
})();
