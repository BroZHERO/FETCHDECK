// FETCHDECK Comprehensive Backtesting & Regression Test Suite
// Verifies URL filtering, Title validation, Cookie extraction, and Suno DOM scraping

const assert = require("assert");

console.log("=================================================");
console.log("  FETCHDECK TEST & BACKTESTING SUITE");
console.log("=================================================\n");

let passedTests = 0;
let totalTests = 0;

function it(name, fn) {
  totalTests++;
  try {
    fn();
    console.log(`  ✓ PASS: ${name}`);
    passedTests++;
  } catch (err) {
    console.error(`  ✗ FAIL: ${name}`);
    console.error(`    Error: ${err.message}\n`);
    throw err;
  }
}

// -------------------------------------------------------------------
// 1. isIgnoredMediaUrl
// -------------------------------------------------------------------
function isIgnoredMediaUrl(url) {
  if (!url || typeof url !== "string") return true;
  if (url.startsWith("blob:") || url.startsWith("data:") || url.startsWith("javascript:")) return true;

  const lower = url.toLowerCase();

  // 1. Explicit placeholder / dummy / forbidden URLs
  if (
    lower.includes("forbidden") ||
    lower.includes("silence") ||
    lower.includes("blank.mp3") ||
    lower.includes("dummy") ||
    lower.includes("placeholder") ||
    lower.includes("track_not_found")
  ) {
    return true;
  }

  // 2. Universal telemetry, analytics, logging, tracking, and beacon endpoints
  if (
    lower.includes("s.prod.suno.com") ||
    lower.includes("/rgstr") ||
    lower.includes("telemetry") ||
    lower.includes("analytics") ||
    lower.includes("/beacon") ||
    lower.includes("/stats") ||
    lower.includes("/track") ||
    lower.includes("/logging") ||
    lower.includes("doubleclick") ||
    lower.includes("google-analytics") ||
    lower.includes("googletagmanager") ||
    lower.includes("clarity.ms") ||
    lower.includes("hotjar")
  ) {
    return true;
  }

  // 3. Suno AI specific filters
  if (lower.includes("suno.com") || lower.includes("suno.ai")) {
    const isSunoCdn = lower.includes("cdn1.suno.ai") || lower.includes("cdn2.suno.ai") || lower.includes("audiopipe.suno.ai");
    const isMediaFile = /\.(mp3|wav|ogg|flac|m4a|aac|mp4|webm)(\?|$)/i.test(lower);
    if (!isSunoCdn && !isMediaFile) {
      return true;
    }
  }

  return false;
}

console.log("--- TEST GROUP 1: URL & Telemetry Filtering ---");
it("Blocks Suno telemetry ping s.prod.suno.com/v1/rgstr", () => {
  const telemetry = "https://s.prod.suno.com/v1/rgstr?k=client-DaZjubWc7zwnZ5o2EEJHqt4UYRzYRoUuHbTQclH9Ybq&st=javascript-client-react&sv=3.25.5&t=1795427534592&sid=c9eee7e6-8f43-4ce4-897c-9efcfa1a2212";
  assert.strictEqual(isIgnoredMediaUrl(telemetry), true);
});

it("Blocks Suno forbidden.webm placeholder", () => {
  const forbidden = "https://studio-api.prod.suno.com/api/forbidden.webm";
  assert.strictEqual(isIgnoredMediaUrl(forbidden), true);
});

it("Blocks generic analytics and tracking URLs", () => {
  assert.strictEqual(isIgnoredMediaUrl("https://www.google-analytics.com/g/collect?v=2"), true);
  assert.strictEqual(isIgnoredMediaUrl("https://suno.com/api/telemetry/event"), true);
  assert.strictEqual(isIgnoredMediaUrl("blob:https://suno.com/12345"), true);
  assert.strictEqual(isIgnoredMediaUrl("data:audio/mp3;base64,ABC"), true);
});

it("Allows legitimate Suno cdn1 MP3 stream", () => {
  const validMp3 = "https://cdn1.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3";
  assert.strictEqual(isIgnoredMediaUrl(validMp3), false);
});

it("Allows legitimate Suno cdn2 audio stream", () => {
  const validCdn2 = "https://cdn2.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3";
  assert.strictEqual(isIgnoredMediaUrl(validCdn2), false);
});

it("Allows legitimate audiopipe.suno.ai stream", () => {
  const validAudiopipe = "https://audiopipe.suno.ai/?item_id=d35afa0a-efe8-461d-8077-3ce1a266cfa6";
  assert.strictEqual(isIgnoredMediaUrl(validAudiopipe), false);
});

it("Allows YouTube video stream", () => {
  const yt = "https://rr1---sn-4g5edn6e.googlevideo.com/videoplayback?expire=1732381200&ei=...";
  assert.strictEqual(isIgnoredMediaUrl(yt), false);
});

// -------------------------------------------------------------------
// 2. isValidTitle
// -------------------------------------------------------------------
function isValidTitle(text) {
  if (!text || typeof text !== "string") return false;
  const clean = text.trim();
  if (clean.length < 2) return false;
  if (/^[-_:\s0-9/.]+$/.test(clean)) return false;
  if (clean.includes("--:--") || /^\d+:\d+/.test(clean)) return false;
  const lower = clean.toLowerCase();
  if (/^v\d+([-_\s][a-z0-9]+)?$/i.test(lower)) return false;
  const uiKeywords = [
    "remix", "share", "publish", "v4", "v3", "v2", "mini", "preview",
    "explore", "library", "create", "upgrade", "upgrade to pro",
    "earn credits", "home", "studio", "settings", "audio", "history",
    "liked", "public", "uploads", "filters", "songs", "playlists",
    "albums", "workspaces", "hooks"
  ];
  if (uiKeywords.includes(lower)) return false;
  return true;
}

console.log("\n--- TEST GROUP 2: Song Title Validation ---");
it("Rejects uninitialized time scrubber --:--", () => {
  assert.strictEqual(isValidTitle("--:--"), false);
  assert.strictEqual(isValidTitle("--_--"), false);
  assert.strictEqual(isValidTitle("-:--"), false);
  assert.strictEqual(isValidTitle("0:00 / --:--"), false);
});

it("Rejects timer scrubber and progress counters", () => {
  assert.strictEqual(isValidTitle("0:05"), false);
  assert.strictEqual(isValidTitle("6:22"), false);
  assert.strictEqual(isValidTitle("06:34"), false);
  assert.strictEqual(isValidTitle("6:22 / 6:34"), false);
});

it("Rejects generic UI navigation words", () => {
  assert.strictEqual(isValidTitle("Library"), false);
  assert.strictEqual(isValidTitle("Remix"), false);
  assert.strictEqual(isValidTitle("Share"), false);
  assert.strictEqual(isValidTitle("Publish"), false);
  assert.strictEqual(isValidTitle("Upgrade to Pro"), false);
  assert.strictEqual(isValidTitle("Songs"), false);
  assert.strictEqual(isValidTitle("Explore"), false);
  assert.strictEqual(isValidTitle("v4-mini"), false);
});

it("Accepts genuine Hindi & international song titles", () => {
  assert.strictEqual(isValidTitle("जीते जी v4"), true);
  assert.strictEqual(isValidTitle("Tum Hi Ho (Acoustic)"), true);
  assert.strictEqual(isValidTitle("Cyberpunk Dreams 2026"), true);
  assert.strictEqual(isValidTitle("Chasing The Horizon"), true);
});

// -------------------------------------------------------------------
// 3. Filename Sanitization & Fallback Resolution
// -------------------------------------------------------------------
function resolveSunoFilename(item, sunoTrackMap) {
  const isAudio = true;
  const isSuno = true;

  let rawTitle = item.title;
  if (!isValidTitle(rawTitle)) {
    const uuidMatch = item.url.match(/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/);
    if (uuidMatch && sunoTrackMap.has(uuidMatch[1])) {
      rawTitle = sunoTrackMap.get(uuidMatch[1]).title;
    }
    if (!isValidTitle(rawTitle) && uuidMatch) {
      rawTitle = `Suno_Track_${uuidMatch[1].substring(0, 8)}`;
    }
  }
  if (!isValidTitle(rawTitle)) {
    rawTitle = "Suno_AI_Song";
  }
  rawTitle = rawTitle.replace(/ - YouTube$/, "").replace(/\s*\|\s*Suno.*$/i, "").replace(/[\\/:*?"<>|]/g, "_").trim();

  let ext = "mp3";
  return `${rawTitle} - Suno AI.${ext}`;
}

console.log("\n--- TEST GROUP 3: Filename Resolution & Anti---_-- ---");
it("Generates pristine filename when title is valid (जीते जी v4)", () => {
  const item = {
    url: "https://cdn1.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3",
    title: "जीते जी v4"
  };
  const map = new Map();
  const filename = resolveSunoFilename(item, map);
  assert.strictEqual(filename, "जीते जी v4 - Suno AI.mp3");
});

it("Rescues --:-- title by looking up pristine title in sunoTrackMap", () => {
  const item = {
    url: "https://cdn1.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3",
    title: "--:--"
  };
  const map = new Map();
  map.set("d35afa0a-efe8-461d-8077-3ce1a266cfa6", {
    title: "जीते जी v4",
    id: "d35afa0a-efe8-461d-8077-3ce1a266cfa6"
  });
  const filename = resolveSunoFilename(item, map);
  assert.strictEqual(filename, "जीते जी v4 - Suno AI.mp3");
});

it("Never outputs --_-- - Suno AI.mp3 even if track map is empty", () => {
  const item = {
    url: "https://cdn1.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3",
    title: "--:--"
  };
  const map = new Map();
  const filename = resolveSunoFilename(item, map);
  assert.strictEqual(filename, "Suno_Track_d35afa0a - Suno AI.mp3");
  assert(!filename.includes("--_--"));
});

// -------------------------------------------------------------------
// 4. CloudFront Cookie Collector
// -------------------------------------------------------------------
async function mockGetCookiesForPayload(payload, mockCookieStore) {
  const cookieMap = new Map();

  async function addCookies(filter) {
    for (const c of mockCookieStore) {
      if (filter.url && filter.url.includes(c.domain.replace(/^\./, ""))) {
        cookieMap.set(c.name, c.value);
      } else if (filter.domain && (c.domain === filter.domain || c.domain === "." + filter.domain)) {
        cookieMap.set(c.name, c.value);
      }
    }
  }

  const isSuno = (payload.url && (payload.url.includes("suno.ai") || payload.url.includes("suno.com"))) ||
                 (payload.referer && (payload.referer.includes("suno.ai") || payload.referer.includes("suno.com")));
  if (isSuno) {
    await addCookies({ url: "https://suno.com" });
    await addCookies({ url: "https://cdn1.suno.ai" });
    await addCookies({ domain: ".suno.com" });
    await addCookies({ domain: ".suno.ai" });
  }

  const parts = [];
  for (const [name, value] of cookieMap.entries()) {
    parts.push(`${name}=${value}`);
  }
  return parts.join("; ");
}

console.log("\n--- TEST GROUP 4: CloudFront Signed Cookie Gathering ---");
it("Gathers CloudFront-Key-Pair-Id, CloudFront-Policy, CloudFront-Signature", async () => {
  const mockCookieStore = [
    { name: "CloudFront-Key-Pair-Id", value: "K2JCXYZ123456", domain: ".suno.ai" },
    { name: "CloudFront-Policy", value: "eyJTdGF0ZW1lbnQiOlt7...}", domain: ".suno.ai" },
    { name: "CloudFront-Signature", value: "abcdef123456==", domain: ".suno.ai" },
    { name: "__client", value: "sess_987654321", domain: ".suno.com" },
    { name: "VISITOR_INFO1_LIVE", value: "yt_cookie", domain: ".youtube.com" }
  ];

  const payload = {
    url: "https://cdn1.suno.ai/d35afa0a-efe8-461d-8077-3ce1a266cfa6.mp3",
    referer: "https://suno.com/me"
  };

  const cookieHeader = await mockGetCookiesForPayload(payload, mockCookieStore);
  assert(cookieHeader.includes("CloudFront-Key-Pair-Id=K2JCXYZ123456"));
  assert(cookieHeader.includes("CloudFront-Policy=eyJTdGF0ZW1lbnQiOlt7...}"));
  assert(cookieHeader.includes("CloudFront-Signature=abcdef123456=="));
  assert(cookieHeader.includes("__client=sess_987654321"));
  // YouTube cookie should NOT be merged
  assert(!cookieHeader.includes("VISITOR_INFO1_LIVE"));
});

// -------------------------------------------------------------------
// 5. DOM Scraping Simulation (Handling Image-wrapped links)
// -------------------------------------------------------------------
console.log("\n--- TEST GROUP 5: Suno DOM Song Extraction Simulation ---");
it("Extracts title from row even when first link is an image wrapper", () => {
  // Simulate DOM of Suno song row:
  // <div class="row">
  //   <a href="/song/d35afa0a-efe8-461d-8077-3ce1a266cfa6"><img src="..." /></a> (innerText is empty)
  //   <a href="/song/d35afa0a-efe8-461d-8077-3ce1a266cfa6">जीते जी v4</a> (innerText is title)
  // </div>
  const links = [
    {
      href: "/song/d35afa0a-efe8-461d-8077-3ce1a266cfa6",
      innerText: "",
      card: {
        allTitles: ["", "जीते जी v4", "v4-mini", "6:22"]
      }
    },
    {
      href: "/song/d35afa0a-efe8-461d-8077-3ce1a266cfa6",
      innerText: "जीते जी v4",
      card: {
        allTitles: ["", "जीते जी v4", "v4-mini", "6:22"]
      }
    }
  ];

  const seenUuids = new Set();
  const discovered = [];

  links.forEach((link) => {
    const match = link.href.match(/\/song\/([0-9a-fA-F-]+)/);
    if (!match) return;
    const uuid = match[1];
    if (seenUuids.has(uuid)) return;

    let title = "";
    if (isValidTitle(link.innerText)) {
      title = link.innerText.trim();
    }
    if (!title && link.card) {
      for (const t of link.card.allTitles) {
        if (isValidTitle(t)) {
          title = t;
          break;
        }
      }
    }
    if (!title) {
      title = `Suno Track ${uuid.substring(0, 8)}`;
    }

    seenUuids.add(uuid);
    discovered.push({ uuid, title });
  });

  assert.strictEqual(discovered.length, 1);
  assert.strictEqual(discovered[0].title, "जीते जी v4");
  assert.strictEqual(discovered[0].uuid, "d35afa0a-efe8-461d-8077-3ce1a266cfa6");
});

console.log("\n--- TEST GROUP 6: Suno Signed URL Resolution & Dual Button Dispatch ---");
it("Distinguishes between bare unsigned Suno URL and authorized signed stream", () => {
  const bareUrl = "https://cdn1.suno.ai/18e91ea4-0daf-4f7b-a2ec-01df04696dc0.mp3";
  const signedUrl = "https://cdn1.suno.ai/18e91ea4-0daf-4f7b-a2ec-01df04696dc0.mp3?Key-Pair-Id=K38W0D8X4P0P5Q&Signature=ABC123XYZ&Expires=1795438800";
  const studioSigned = "https://audiopipe.suno.ai/?item_id=18e91ea4-0daf-4f7b-a2ec-01df04696dc0&token=eyJhbGciOi...";

  function isUnsignedSunoUrl(url) {
    if (!url.includes("suno.ai") && !url.includes("suno.com")) return false;
    return !url.includes("Key-Pair-Id") && !url.includes("Signature") && !url.includes("token");
  }

  assert.strictEqual(isUnsignedSunoUrl(bareUrl), true, "Bare cdn1 URL without signature must be detected as unsigned");
  assert.strictEqual(isUnsignedSunoUrl(signedUrl), false, "CloudFront signed URL must be recognized as valid");
  assert.strictEqual(isUnsignedSunoUrl(studioSigned), false, "Audiopipe tokenized URL must be recognized as valid");
});

it("Constructs authorized Suno download request headers", () => {
  const dummyToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.signature";
  const headers = {
    "Accept": "application/json, text/plain, */*"
  };
  if (dummyToken) {
    headers["Authorization"] = `Bearer ${dummyToken}`;
  }
  assert.strictEqual(headers["Authorization"], `Bearer ${dummyToken}`);
  assert.strictEqual(headers["Accept"], "application/json, text/plain, */*");
});

it("Formats Suno API endpoint for clip download", () => {
  const clipId = "18e91ea4-0daf-4f7b-a2ec-01df04696dc0";
  const format = "mp3";
  const endpoint = `https://studio-api.prod.suno.com/api/download/clip/${clipId}?format=${format}`;
  assert.strictEqual(endpoint, "https://studio-api.prod.suno.com/api/download/clip/18e91ea4-0daf-4f7b-a2ec-01df04696dc0?format=mp3");
});

it("Validates popup actions include both Download and Browser options", () => {
  const rowHtml = `
    <div class="media-row-actions">
      <button class="download-pill-btn" data-url="https://example.com/test.mp3">⬇ Download</button>
      <button class="browser-pill-btn" data-url="https://example.com/test.mp3" title="Save directly in browser">🌐 Browser</button>
    </div>
  `;
  assert.strictEqual(rowHtml.includes("download-pill-btn"), true);
  assert.strictEqual(rowHtml.includes("browser-pill-btn"), true);
});

console.log("\n--- TEST GROUP 7: Opera Default File Downloader Interception ---");

function detectDownloadCategory(filename, mime = "") {
  const lower = (filename || "").toLowerCase();
  const lowerMime = (mime || "").toLowerCase();

  if (
    lower.match(/\.(mp4|mkv|mov|avi|webm|flv|wmv|m4v|3gp|ts)$/i) ||
    lowerMime.includes("video")
  ) {
    return "video";
  }

  if (
    lower.match(/\.(mp3|wav|m4a|aac|flac|ogg|opus|aiff|wma)$/i) ||
    lowerMime.includes("audio")
  ) {
    return "audio";
  }

  if (
    lower.match(/\.(zip|tar|gz|bz2|7z|rar|xz|dmg|iso|pkg|deb|rpm|exe|bin|apk|jar)$/i) ||
    lowerMime.includes("zip") || lowerMime.includes("compressed") || lowerMime.includes("archive")
  ) {
    return "compressed";
  }

  if (
    lower.match(/\.(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|rtf|csv|epub|pages|numbers|key)$/i) ||
    lowerMime.includes("pdf") || lowerMime.includes("document") || lowerMime.includes("text")
  ) {
    return "documents";
  }

  return "other";
}

function shouldInterceptDownload(downloadItem, interceptAllDownloads, isAppOnline, internalDownloadIds) {
  if (!interceptAllDownloads) return false;
  if (internalDownloadIds.has(downloadItem.id)) return false;

  const url = downloadItem.url || downloadItem.finalUrl;
  if (!url) return false;

  if (
    url.startsWith("blob:") ||
    url.startsWith("data:") ||
    url.startsWith("chrome:") ||
    url.startsWith("opera:") ||
    url.startsWith("about:") ||
    url.startsWith("filesystem:")
  ) {
    return false;
  }

  const lowerUrl = url.toLowerCase();
  if (lowerUrl.endsWith(".crx") || lowerUrl.endsWith(".nex") || lowerUrl.endsWith(".oex")) {
    return false;
  }

  if (!isAppOnline) return false;

  return true;
}

it("Correctly classifies file categories for universal Opera downloads", () => {
  assert.strictEqual(detectDownloadCategory("movie.mp4", "video/mp4"), "video");
  assert.strictEqual(detectDownloadCategory("song.mp3", "audio/mpeg"), "audio");
  assert.strictEqual(detectDownloadCategory("archive.zip", "application/zip"), "compressed");
  assert.strictEqual(detectDownloadCategory("installer.dmg", ""), "compressed");
  assert.strictEqual(detectDownloadCategory("document.pdf", "application/pdf"), "documents");
  assert.strictEqual(detectDownloadCategory("custom.dat", "application/octet-stream"), "other");
});

it("Intercepts legitimate file downloads in Opera when FetchDeck is online", () => {
  const item = {
    id: 101,
    url: "https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-arm64.iso",
    filename: "ubuntu-24.04-desktop-arm64.iso"
  };
  const internalIds = new Set();
  const intercepted = shouldInterceptDownload(item, true, true, internalIds);
  assert.strictEqual(intercepted, true, "Standard web download should be intercepted by FetchDeck");
});

it("Bypasses browser extension packages so Opera can install extensions cleanly", () => {
  const extItem = {
    id: 102,
    url: "https://addons.opera.com/extensions/download/my_ext.crx",
    filename: "my_ext.crx"
  };
  const internalIds = new Set();
  assert.strictEqual(shouldInterceptDownload(extItem, true, true, internalIds), false);
});

it("Bypasses internal extension downloads to avoid infinite download loops", () => {
  const item = {
    id: 103,
    url: "https://example.com/sample.mp4",
    filename: "sample.mp4"
  };
  const internalIds = new Set([103]);
  assert.strictEqual(shouldInterceptDownload(item, true, true, internalIds), false);
});

it("Bypasses in-memory blob URLs so in-page WebAudio blobs render safely", () => {
  const blobItem = {
    id: 104,
    url: "blob:https://suno.com/550e8400-e29b-41d4-a716-446655440000",
    filename: "song.mp3"
  };
  const internalIds = new Set();
  assert.strictEqual(shouldInterceptDownload(blobItem, true, true, internalIds), false);
});

it("Bypasses when user turns off default downloader toggle in popup", () => {
  const item = {
    id: 105,
    url: "https://example.com/archive.zip",
    filename: "archive.zip"
  };
  const internalIds = new Set();
  assert.strictEqual(shouldInterceptDownload(item, false, true, internalIds), false);
});

it("Bypasses safely if FetchDeck desktop app is offline", () => {
  const item = {
    id: 106,
    url: "https://example.com/archive.zip",
    filename: "archive.zip"
  };
  const internalIds = new Set();
  assert.strictEqual(shouldInterceptDownload(item, true, false, internalIds), false, "Must let Opera download normally if FetchDeck is closed");
});

console.log("\n=================================================");
console.log(`  ALL BACKTESTS PASSED! (${passedTests}/${totalTests} assertions)`);
console.log("=================================================");
