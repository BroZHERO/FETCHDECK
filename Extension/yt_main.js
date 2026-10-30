// MacDownloader YouTube Main-World Bridge Script
// Runs directly in YouTube's main JavaScript context with direct access to player objects, network calls, and runtime
(() => {
  let cachedDecipherer = null;

  // 1. Intercept Network Requests made by YouTube HTML5 Player (Captures 100% valid signed streams)
  const interceptedUrls = new Map(); // itag -> stream item

  function processCapturedUrl(rawUrl) {
    if (!rawUrl || !rawUrl.includes("googlevideo.com/videoplayback")) return;
    try {
      const u = new URL(rawUrl);
      const sparams = (u.searchParams.get("sparams") || "").split(",");
      // Skip 31-byte init segment stubs
      if (sparams.includes("range")) return;

      const itag = parseInt(u.searchParams.get("itag"), 10);
      const sig = u.searchParams.get("sig") || u.searchParams.get("signature");
      if (!itag || !sig) return;

      // Clean playback slice parameters (rn, sq, rbuf, range) to construct Master Stream URL
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

      broadcastStreams();
    } catch (e) {}
  }

  // Hook window.fetch
  const originalFetch = window.fetch;
  window.fetch = async function (...args) {
    try {
      const url = typeof args[0] === "string" ? args[0] : (args[0] && args[0].url);
      if (url) processCapturedUrl(url);
    } catch (e) {}
    return originalFetch.apply(this, args);
  };

  // Hook XMLHttpRequest
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    try {
      if (url) processCapturedUrl(String(url));
    } catch (e) {}
    return originalOpen.apply(this, [method, url, ...rest]);
  };

  // 2. Locate base.js and extract YouTube signature decipher function
  async function getDecipherer() {
    if (cachedDecipherer) return cachedDecipherer;

    try {
      // Find base.js player script URL
      let scriptUrl = null;
      if (window.ytplayer && window.ytplayer.config && window.ytplayer.config.assets && window.ytplayer.config.assets.js) {
        scriptUrl = window.ytplayer.config.assets.js;
      }
      if (!scriptUrl) {
        const scriptTag = Array.from(document.querySelectorAll("script[src]")).find(
          (s) => s.src.includes("/base.js") || s.src.includes("player_ias") || s.src.includes("desktop_polymer")
        );
        if (scriptTag) scriptUrl = scriptTag.src;
      }
      if (!scriptUrl) return null;

      if (scriptUrl.startsWith("//")) scriptUrl = "https:" + scriptUrl;
      if (scriptUrl.startsWith("/")) scriptUrl = window.location.origin + scriptUrl;

      const code = await (await fetch(scriptUrl)).text();

      // yt-dlp proven decipher regex pattern
      const fnNameMatch =
        code.match(/\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$]{2,3})\(/) ||
        code.match(/([a-zA-Z0-9$]{2,3})\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\);/);

      if (!fnNameMatch) return null;
      const fnName = fnNameMatch[1];

      // Extract function body
      const escapedFnName = fnName.replace("$", "\\$");
      const fnBodyMatch = code.match(new RegExp(`${escapedFnName}\\s*=\\s*function\\([a-zA-Z0-9]+\\)\\{([\\s\\S]*?)\\};`));
      if (!fnBodyMatch) return null;

      // Extract helper object name
      const helperMatch = fnBodyMatch[1].match(/([a-zA-Z0-9$]+)\./);
      if (!helperMatch) return null;
      const helperName = helperMatch[1];
      const escapedHelperName = helperName.replace("$", "\\$");

      const helperBodyMatch = code.match(new RegExp(`var\\s+${escapedHelperName}\\s*=\\s*\\{([\\s\\S]*?)\\};`));
      if (!helperBodyMatch) return null;

      const fullCode = `var ${helperName}={${helperBodyMatch[1]}}; var ${fnName}=function(a){${fnBodyMatch[1]}}; return ${fnName}(sig);`;
      cachedDecipherer = new Function("sig", fullCode);
      return cachedDecipherer;
    } catch (e) {
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
    const data = getRawPlayerData();
    const streamingData = data ? JSON.parse(JSON.stringify(data.streamingData || {})) : {};
    const decipher = await getDecipherer();

    const processFormat = (f) => {
      // If we intercepted the exact fully-signed playback stream for this itag, use that master URL!
      if (f.itag && interceptedUrls.has(f.itag)) {
        const captured = interceptedUrls.get(f.itag);
        f.url = captured.url;
        if (captured.size > 0 && !f.contentLength) f.contentLength = String(captured.size);
        return f;
      }

      // Check if format already has a valid signed URL
      if (f.url && (f.url.includes("sig=") || f.url.includes("signature="))) {
        return f;
      }

      // If format has signatureCipher, attempt deciphering
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

    // Include intercepted streams that may not be in player response
    const capturedList = Array.from(interceptedUrls.values());

    window.postMessage(
      {
        type: "MACDL_YT_PLAYER_DATA",
        streamingData: streamingData,
        capturedStreams: capturedList,
        videoDetails: (data && data.videoDetails) || {}
      },
      "*"
    );
  }

  // Periodic and event-driven updates
  window.addEventListener("yt-navigate-finish", () => {
    interceptedUrls.clear();
    setTimeout(broadcastStreams, 400);
    setTimeout(broadcastStreams, 1500);
  });

  window.addEventListener("message", (event) => {
    if (event.data && event.data.type === "MACDL_REQUEST_YT_DATA") {
      broadcastStreams();
    }
  });

  setInterval(broadcastStreams, 2000);
  setTimeout(broadcastStreams, 600);
})();
