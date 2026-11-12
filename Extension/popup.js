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

        const icon = item.type === "audio" ? "🎵" : "🎬";
        const title = item.label || `media_stream_${index + 1}`;
        const formattedSize = item.formattedSize || (item.size > 0 ? ` • ${(item.size / (1024 * 1024)).toFixed(1)} MB` : "");
        const qualityStr = item.quality ? `[${item.quality}] ` : "";
        const dimStr = item.dimensions ? ` • ${item.dimensions}` : "";

        row.innerHTML = `
          <div class="media-info">
            <div class="media-url" title="${item.url}">${icon} ${escapeHtml(title)}</div>
            <div class="media-meta">${qualityStr}${item.combined ? "Full Video" : (item.type === "audio" ? "Audio Only" : "Video + Audio Muxed")}${dimStr}${formattedSize}</div>
          </div>
          <button class="download-pill-btn" data-url="${item.url}">⬇ Download</button>
        `;

        const btn = row.querySelector(".download-pill-btn");
        btn.addEventListener("click", () => {
          let pageTitle = (tab.title || "media").replace(/ - YouTube$/, "").replace(/[\\/:*?"<>|]/g, "_").trim();
          const ext = item.url.includes(".m3u8") ? "mp4" : (item.type === "audio" ? "m4a" : "mp4");
          const safeName = `[${item.quality || index + 1}] ${pageTitle}.${ext}`;
          dispatchDownload(item.url, safeName, item.quality || "HD", tab.url, btn, null, item.audioUrl, item.dimensions);
        });

        mediaList.appendChild(row);
      });
    }
  }

  // Quick URL submission
  quickSendBtn.addEventListener("click", () => {
    const url = quickUrlInput.value.trim();
    if (!url) return;
    dispatchDownload(url, null, "Direct", tab?.url, quickSendBtn, feedbackMsg);
  });

  function dispatchDownload(url, filename, quality, referer, btnElement, feedbackTarget, audioUrl = null, dimensions = null) {
    if (!url || url.startsWith("blob:") || url.startsWith("data:")) {
      if (feedbackTarget) {
        feedbackTarget.style.color = "#ff3b30";
        feedbackTarget.innerText = "Error: Blob URLs cannot be downloaded directly.";
      }
      return;
    }

    const payload = {
      url,
      audioUrl: audioUrl || null,
      filename: filename || url.split("/").pop().split("?")[0] || "download",
      quality: quality || "HD",
      dimensions: dimensions || "",
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
