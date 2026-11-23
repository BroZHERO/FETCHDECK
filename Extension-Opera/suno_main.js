(() => {
  if (window.__macdl_suno_injected) return;
  window.__macdl_suno_injected = true;

  const capturedClips = new Map();

  function extractClips(obj, list = []) {
    if (!obj || typeof obj !== "object") return list;

    if (obj.id && (obj.audio_url || obj.title)) {
      const audioUrl = obj.audio_url || `https://cdn1.suno.ai/${obj.id}.mp3`;
      if (!audioUrl.includes("forbidden")) {
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

  // 1. Intercept window.fetch to capture Suno API feed & song metadata
  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
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
})();
