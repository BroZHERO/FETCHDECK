document.addEventListener("DOMContentLoaded", async () => {
  const statusPill = document.getElementById("statusPill");
  const mediaList = document.getElementById("mediaList");
  const mediaCount = document.getElementById("mediaCount");
  const quickUrlInput = document.getElementById("quickUrlInput");
  const quickSendBtn = document.getElementById("quickSendBtn");
  const feedbackMsg = document.getElementById("feedbackMsg");

  // Check MacDownloader App connectivity
  chrome.runtime.sendMessage({ action: "check_status" }, (res) => {
    if (res && res.online) {
      statusPill.className = "status-pill online";
      statusPill.innerText = "● Connected";
    } else {
      statusPill.className = "status-pill offline";
      statusPill.innerText = "○ App Offline";
    }
  });

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && tab.id) {
    let videoId = null;
    if (tab.url && tab.url.includes("youtube.com")) {
      try {
        const u = new URL(tab.url);
        videoId = u.searchParams.get("v") || (u.pathname.match(/\/shorts\/([a-zA-Z0-9_-]+)/) || [])[1];
      } catch (e) {}
    }

    chrome.runtime.sendMessage({ action: "resolve_universal_media", videoId, url: tab.url, tabId: tab.id }, (res) => {
      if (res && res.streams && res.streams.length > 0) {
        renderPopupMedia(res.streams, tab);
      } else {
        fallbackGetTabMedia(tab);
      }
    });
  }

  function fallbackGetTabMedia(tab) {
    chrome.runtime.sendMessage({ action: "get_tab_media", tabId: tab.id }, (res) => {
      const media = (res && res.media) || [];
      renderPopupMedia(media, tab);
    });
  }

  function renderPopupMedia(media, tab) {
    mediaCount.innerText = media.length;

    if (media.length > 0) {
      mediaList.innerHTML = "";
      media.forEach((item, index) => {
        const row = document.createElement("div");
        row.className = "media-item";

        const isAudio = item.type === "audio" || (item.format && item.format.toLowerCase().includes("audio"));
        const isSuno = (item.url && (item.url.includes(".suno.ai") || item.url.includes(".suno.com") || item.url.includes("audiopipe"))) || (item.label && item.label.includes("Suno AI"));

        const icon = isAudio ? "🎵" : "🎬";
        const title = item.title || item.label || `media_stream_${index + 1}`;
        const formattedSize = item.formattedSize || (item.size > 0 ? ` • ${(item.size / (1024 * 1024)).toFixed(1)} MB` : "");
        const qualityStr = item.quality ? `[${item.quality}] ` : "";
        const dimStr = item.dimensions ? ` • ${item.dimensions}` : "";
        const descType = isSuno ? "Suno AI Master" : (item.combined ? (isAudio ? "Direct Audio" : "Full Video") : (isAudio ? "Audio Only" : "Video + Audio Muxed"));

        row.innerHTML = `
          <div class="media-info">
            <div class="media-url" title="${item.url}">${icon} ${escapeHtml(title)}</div>
            <div class="media-meta">${qualityStr}${descType}${dimStr}${formattedSize}</div>
          </div>
          <button class="download-pill-btn" data-url="${item.url}">⬇ Download</button>
        `;

        const btn = row.querySelector(".download-pill-btn");
        btn.addEventListener("click", () => {
          let baseTitle = item.title || (tab.title || "media").replace(/ - YouTube$/, "").replace(/\s*\|\s*Suno.*$/i, "").replace(/[\\/:*?"<>|]/g, "_").trim();
          let ext = "mp4";
          if (isAudio || isSuno) {
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
          const safeName = isSuno
            ? `${baseTitle || "Suno_Track"} - Suno AI.${ext}`
            : `[${item.quality || (isAudio ? "Audio" : index + 1)}] ${baseTitle}.${ext}`;

          dispatchDownload(
            item.url,
            safeName,
            item.quality || (isAudio ? "320 kbps MP3" : "HD"),
            tab.url,
            btn,
            null,
            item.audioUrl,
            item.dimensions,
            isAudio || isSuno ? "audio" : "video",
            item.thumbnail
          );
        });

        mediaList.appendChild(row);
      });
    }
  }

  // Quick URL submission
  quickSendBtn.addEventListener("click", () => {
    const url = quickUrlInput.value.trim();
    if (!url) return;
    const isAudioUrl = url.match(/\.(mp3|wav|m4a|aac|flac|ogg|opus)(\?|$)/i) || url.includes(".suno.ai") || url.includes("audiopipe");
    dispatchDownload(url, null, isAudioUrl ? "Audio" : "Direct", tab?.url, quickSendBtn, feedbackMsg, null, null, isAudioUrl ? "audio" : "video");
  });

  function dispatchDownload(url, filename, quality, referer, btnElement, feedbackTarget, audioUrl = null, dimensions = null, category = null, thumbnail = null) {
    if (!url || url.startsWith("blob:") || url.startsWith("data:")) {
      if (feedbackTarget) {
        feedbackTarget.style.color = "#ff3b30";
        feedbackTarget.innerText = "Error: Blob URLs cannot be downloaded directly.";
      }
      return;
    }

    const isAudio = category === "audio" || url.match(/\.(mp3|wav|m4a|aac|flac|ogg|opus)(\?|$)/i) || url.includes(".suno.ai") || url.includes("audiopipe");

    const payload = {
      url,
      audioUrl: audioUrl || null,
      filename: filename || url.split("/").pop().split("?")[0] || "download",
      quality: quality || (isAudio ? "320 kbps MP3" : "HD"),
      dimensions: dimensions || "",
      category: isAudio ? "audio" : (category || "video"),
      thumbnail: thumbnail || null,
      referer: referer || "",
      userAgent: navigator.userAgent
    };

    chrome.runtime.sendMessage({ action: "send_to_app", payload }, (res) => {
      if (res && res.success) {
        if (btnElement) btnElement.innerText = "✓ Sent";
        if (feedbackTarget) {
          feedbackTarget.style.color = "#34c759";
          feedbackTarget.innerText = "Sent to FETCHDECK!";
        }
      } else {
        if (btnElement) btnElement.innerText = "Failed";
        if (feedbackTarget) {
          feedbackTarget.style.color = "#ff3b30";
          feedbackTarget.innerText = `Failed: ${(res && res.error) || "Is FETCHDECK app running?"}`;
        }
      }
    });
  }

  function escapeHtml(str) {
    if (!str) return "";
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
});
