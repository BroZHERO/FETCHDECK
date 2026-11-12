// FETCHDECK YouTube Main-World Bridge Script
// Ultra-lightweight, zero-lag interceptor running in YouTube's main JavaScript context
(() => {
  if (window.__fetchdeck_yt_initialized) return;
  window.__fetchdeck_yt_initialized = true;

  const originalFetch = window.fetch;
  const originalOpen = XMLHttpRequest.prototype.open;

  const interceptedUrls = new Map(); // itag -> stream item
  let cachedDecipherer = null;
  let isDeciphering = false;
  let broadcastTimer = null;

  // Debounced broadcast to prevent any possibility of event storms
  function triggerBroadcast() {
    if (broadcastTimer) return;
    broadcastTimer = setTimeout(() => {
      broadcastTimer = null;
      broadcastStreams();
    }, 250);
  }

  // 1. Silent URL collector (NO recursive calls, NO network fetches, NO side effects)
  function recordUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== "string" || !rawUrl.includes("googlevideo.com/videoplayback")) return;
    try {
      const u = new URL(rawUrl);
      const range = u.searchParams.get("range") || "";
      if (range === "0-31" || range === "0-100") return;

      const itag = parseInt(u.searchParams.get("itag"), 10);
      if (!itag) return;

      const hasAuth =
        u.searchParams.has("sig") ||
        u.searchParams.has("signature") ||
        u.searchParams.has("lsig") ||
        u.searchParams.has("expire") ||
        u.searchParams.has("id");
      if (!hasAuth) return;

      const clean = new URL(rawUrl);
      clean.searchParams.delete("range");
      clean.searchParams.delete("rn");
      clean.searchParams.delete("sq");
      clean.searchParams.delete("rbuf");
      const cleanUrl = clean.toString();

      const clen = parseInt(u.searchParams.get("clen"), 10) || 0;

      interceptedUrls.set(itag, {
        itag: itag,
        url: cleanUrl,
        size: clen,
        timestamp: Date.now()
      });
    } catch (e) {}
  }

  // Hook window.fetch using originalFetch (zero recursion)
  window.fetch = function (...args) {
    try {
      const url = typeof args[0] === "string" ? args[0] : (args[0] && args[0].url);
      if (url) recordUrl(url);
    } catch (e) {}
    return originalFetch.apply(this, args);
  };

  // Hook XMLHttpRequest.open (zero recursion)
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    try {
      if (url) recordUrl(String(url));
    } catch (e) {}
    return originalOpen.apply(this, [method, url, ...rest]);
  };

  // On-demand resource scanner (called only when user clicks FetchDeck button)
  function scanRecentResources() {
    try {
      if (typeof performance !== "undefined" && typeof performance.getEntriesByType === "function") {
        const entries = performance.getEntriesByType("resource");
        for (let i = Math.max(0, entries.length - 80); i < entries.length; i++) {
          const entry = entries[i];
          if (entry.name && entry.name.includes("googlevideo.com/videoplayback")) {
            recordUrl(entry.name);
          }
        }
      }
      const videos = document.querySelectorAll("video");
      for (const v of videos) {
        if (v.src && v.src.includes("googlevideo.com")) recordUrl(v.src);
        if (v.currentSrc && v.currentSrc.includes("googlevideo.com")) recordUrl(v.currentSrc);
      }
    } catch (e) {}
  }

  // Safe signature decipher extractor using originalFetch
  async function getDecipherer() {
    if (cachedDecipherer) return cachedDecipherer;
    if (isDeciphering) return null;
    isDeciphering = true;

    try {
      let scriptUrl = null;
      if (window.ytplayer && window.ytplayer.config && window.ytplayer.config.assets && window.ytplayer.config.assets.js) {
        scriptUrl = window.ytplayer.config.assets.js;
      }
      if (!scriptUrl) {
        const scriptTag = Array.from(document.querySelectorAll("script[src]")).find(
          (s) => s.src.includes("/base.js") || s.src.includes("player_ias")
        );
        if (scriptTag) scriptUrl = scriptTag.src;
      }
      if (!scriptUrl) {
        isDeciphering = false;
        return null;
      }

      if (scriptUrl.startsWith("//")) scriptUrl = "https:" + scriptUrl;
      if (scriptUrl.startsWith("/")) scriptUrl = window.location.origin + scriptUrl;

      // Use unhooked originalFetch to guarantee no interception
      const res = await originalFetch.call(window, scriptUrl);
      if (!res.ok) {
        isDeciphering = false;
        return null;
      }
      const code = await res.text();

      const fnNameMatch =
        code.match(/\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$]{2,3})\(/) ||
        code.match(/([a-zA-Z0-9$]{2,3})\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\);/);

      if (!fnNameMatch) {
        isDeciphering = false;
        return null;
      }
      const fnName = fnNameMatch[1];
      const escapedFnName = fnName.replace("$", "\\$");

      const fnBodyMatch = code.match(new RegExp(`${escapedFnName}\\s*=\\s*function\\([a-zA-Z0-9]+\\)\\{([\\s\\S]*?)\\};`));
      if (!fnBodyMatch) {
        isDeciphering = false;
        return null;
      }

      const helperMatch = fnBodyMatch[1].match(/([a-zA-Z0-9$]+)\./);
      if (!helperMatch) {
        isDeciphering = false;
        return null;
      }
      const helperName = helperMatch[1];
      const escapedHelperName = helperName.replace("$", "\\$");

      const helperBodyMatch = code.match(new RegExp(`var\\s+${escapedHelperName}\\s*=\\s*\\{([\\s\\S]*?)\\};`));
      if (!helperBodyMatch) {
        isDeciphering = false;
        return null;
      }

      const fullCode = `var ${helperName}={${helperBodyMatch[1]}}; var ${fnName}=function(a){${fnBodyMatch[1]}}; return ${fnName}(sig);`;
      cachedDecipherer = new Function("sig", fullCode);
      isDeciphering = false;
      return cachedDecipherer;
    } catch (e) {
      isDeciphering = false;
      return null;
    }
  }

  function getRawPlayerData() {
    try {
      const player = document.getElementById("movie_player");
      if (player && typeof player.getPlayerResponse === "function") {
        const resp = player.getPlayerResponse();
        if (resp && resp.streamingData) return resp;
      }
    } catch (e) {}

    try {
      if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.streamingData) {
        return window.ytInitialPlayerResponse;
      }
    } catch (e) {}

    return null;
  }

  async function broadcastStreams() {
    try {
      const data = getRawPlayerData();
      const streamingData = data ? JSON.parse(JSON.stringify(data.streamingData || {})) : {};
      const decipher = await getDecipherer();

      const processFormat = (f) => {
        if (!f) return f;
        if (f.itag && interceptedUrls.has(f.itag)) {
          const captured = interceptedUrls.get(f.itag);
          f.url = captured.url;
          if (captured.size > 0 && !f.contentLength) f.contentLength = String(captured.size);
          return f;
        }

        if (f.url && (f.url.includes("sig=") || f.url.includes("signature=") || f.url.includes("lsig=") || f.url.includes("expire="))) {
          return f;
        }

        const cipher = f.signatureCipher || f.cipher;
        if (cipher) {
          try {
            const params = new URLSearchParams(cipher);
            const rawUrl = params.get("url");
            const s = params.get("s");
            const sp = params.get("sp") || "sig";
            if (rawUrl && s && decipher) {
              const sig = decipher(s);
              if (sig) {
                f.url = `${rawUrl}&${sp}=${encodeURIComponent(sig)}`;
              }
            }
          } catch (e) {}
        }
        return f;
      };

      if (streamingData.formats) {
        streamingData.formats = streamingData.formats.map(processFormat);
      }
      if (streamingData.adaptiveFormats) {
        streamingData.adaptiveFormats = streamingData.adaptiveFormats.map(processFormat);
      }

      window.postMessage(
        {
          type: "MACDL_YT_PLAYER_DATA",
          streamingData: streamingData,
          capturedStreams: Array.from(interceptedUrls.values()),
          videoDetails: (data && data.videoDetails) || {}
        },
        "*"
      );
    } catch (e) {}
  }

  // Navigation listener: resets captured URLs for new video
  window.addEventListener("yt-navigate-finish", () => {
    interceptedUrls.clear();
    cachedDecipherer = null;
    setTimeout(() => {
      scanRecentResources();
      triggerBroadcast();
    }, 400);
  });

  // Explicit user click listener: scans resources and broadcasts immediately
  window.addEventListener("message", (event) => {
    if (event.data && event.data.type === "MACDL_REQUEST_YT_DATA") {
      scanRecentResources();
      broadcastStreams();
    }
  });

  // Initial single check on page load
  setTimeout(() => {
    scanRecentResources();
    triggerBroadcast();
  }, 600);
})();
