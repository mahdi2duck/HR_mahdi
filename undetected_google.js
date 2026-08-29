import { chromium } from "playwright";
import { newInjectedContext } from "fingerprint-injector";
import { SocksProxyAgent } from "socks-proxy-agent";
import axios from "axios";
import tr from "tor-request";
import fs from "fs/promises";
import "dotenv/config";

// ── Undetected Google Visitor via Tor ───────────────────────────────────────
// Usage:
//   node undetected_google.js                               → visit google.com in loop
//   node undetected_google.js search="boston plumbers"      → search Google for term
//   node undetected_google.js url=https://example.com       → visit custom URL
//   node undetected_google.js threads=3                     → parallel browsers
//   node undetected_google.js rotations=5                   → rotate IPs N times
//   node undetected_google.js screenshot=false              → skip screenshots

const args = process.argv.slice(2);
let targetUrl = "https://www.google.com";
let searchQuery = null;
let enableScreenshot = true;
let threads = 1;
let rotations = 1;

args.forEach((arg) => {
  if (arg.startsWith("search=")) {
    searchQuery = arg.slice(7).replace(/^["']|["']$/g, "");
  }
  if (arg.startsWith("url=")) {
    targetUrl = arg.slice(4);
  }
  if (arg.startsWith("threads=")) {
    threads = parseInt(arg.split("=")[1], 10) || 1;
  }
  if (arg.startsWith("rotation=") || arg.startsWith("rotations=") || arg.startsWith("rot=")) {
    rotations = parseInt(arg.split("=")[1], 10) || 1;
  }
  if (arg.startsWith("screenshot=")) {
    enableScreenshot = arg.split("=")[1].toLowerCase() !== "false";
  }
});

// ── Tor instances ───────────────────────────────────────────────────────────
const torInstances = [
  { socksPort: 9050, controlPort: 9051 },
  { socksPort: 9150, controlPort: 9151 },
  { socksPort: 9250, controlPort: 9251 },
];

// ── Helpers ─────────────────────────────────────────────────────────────────
function generateRandomNumber(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

const weightedRandom = (weights) => {
  let totalWeight = weights.reduce((sum, weight) => sum + weight.weight, 0);
  let random = Math.random() * totalWeight;
  for (let i = 0; i < weights.length; i++) {
    if (random < weights[i].weight) return weights[i].value;
    random -= weights[i].weight;
  }
};

const preferences = [
  { value: { device: "desktop", os: "windows", browser: "chrome" }, weight: 20 },
  { value: { device: "mobile", os: "android", browser: "chrome" }, weight: 100 },
];

// ── Timezone fetcher (through Tor SOCKS) ────────────────────────────────────
const checkTz = async (socksPort) => {
  const proxyAgent = new SocksProxyAgent(`socks5://127.0.0.1:${socksPort}`);
  try {
    const response = await axios.get(
      "https://worker-purple-wind-1de7.idrissimahdi2020.workers.dev",
      {
        httpAgent: proxyAgent,
        httpsAgent: proxyAgent,
        timeout: 15000,
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        },
        family: 4,
      }
    );
    return response.data.trim() || undefined;
  } catch (error) {
    console.error("Error fetching timezone:", error.message);
    return undefined;
  }
};

// ── IP checker (through Tor SOCKS) ──────────────────────────────────────────
const checkTorIP = async (socksPort) => {
  const proxyAgent = new SocksProxyAgent(`socks5://127.0.0.1:${socksPort}`);
  try {
    const response = await axios.get("https://httpbin.org/ip", {
      httpAgent: proxyAgent,
      httpsAgent: proxyAgent,
      timeout: 15000,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
      },
      family: 4,
    });
    return response.data.origin;
  } catch {
    return "Offline/Error";
  }
};

// ── Tor session renewal ─────────────────────────────────────────────────────
const renewTorSession = (myTor) => {
  return new Promise((resolve, reject) => {
    tr.TorControlPort.port = myTor.controlPort;
    tr.TorControlPort.password = "mahdi2019";
    tr.newTorSession((err) => {
      if (err) return reject(err);
      resolve();
    });
  });
};

// ── Anti-detection: Canvas / Audio / WebGL / ClientRects noise ──────────────
export const generateNoise = () => {
  const shift = {
    r: Math.floor(Math.random() * 5) - 2,
    g: Math.floor(Math.random() * 5) - 2,
    b: Math.floor(Math.random() * 5) - 2,
    a: Math.floor(Math.random() * 5) - 2,
  };
  const webglNoise = (Math.random() - 0.5) * 0.01;
  const clientRectsNoise = {
    deltaX: (Math.random() - 0.5) * 2,
    deltaY: (Math.random() - 0.5) * 2,
  };
  const audioNoise = (Math.random() - 0.5) * 0.000001;
  return { shift, webglNoise, clientRectsNoise, audioNoise };
};

export const noisifyScript = (noise) => `
  (function() {
    const noise = ${JSON.stringify(noise)};

    // Canvas Noisify
    const getImageData = CanvasRenderingContext2D.prototype.getImageData;
    const noisify = function (canvas, context) {
      if (context) {
        const shift = noise.shift;
        const width = canvas.width;
        const height = canvas.height;
        if (width && height) {
          const imageData = getImageData.apply(context, [0, 0, width, height]);
          for (let i = 0; i < height; i++) {
            for (let j = 0; j < width; j++) {
              const n = ((i * (width * 4)) + (j * 4));
              imageData.data[n + 0] = imageData.data[n + 0] + shift.r;
              imageData.data[n + 1] = imageData.data[n + 1] + shift.g;
              imageData.data[n + 2] = imageData.data[n + 2] + shift.b;
              imageData.data[n + 3] = imageData.data[n + 3] + shift.a;
            }
          }
          context.putImageData(imageData, 0, 0); 
        }
      }
    };
    HTMLCanvasElement.prototype.toBlob = new Proxy(HTMLCanvasElement.prototype.toBlob, {
      apply(target, self, args) {
        noisify(self, self.getContext("2d"));
        return Reflect.apply(target, self, args);
      }
    });
    HTMLCanvasElement.prototype.toDataURL = new Proxy(HTMLCanvasElement.prototype.toDataURL, {
      apply(target, self, args) {
        noisify(self, self.getContext("2d"));
        return Reflect.apply(target, self, args);
      }
    });
    CanvasRenderingContext2D.prototype.getImageData = new Proxy(CanvasRenderingContext2D.prototype.getImageData, {
      apply(target, self, args) {
        noisify(self.canvas, self);
        return Reflect.apply(target, self, args);
      }
    });

    // Audio Noisify
    const originalGetChannelData = AudioBuffer.prototype.getChannelData;
    AudioBuffer.prototype.getChannelData = function() {
      const results = originalGetChannelData.apply(this, arguments);
      for (let i = 0; i < results.length; i++) {
        results[i] += noise.audioNoise;
      }
      return results;
    };
    const originalCopyFromChannel = AudioBuffer.prototype.copyFromChannel;
    AudioBuffer.prototype.copyFromChannel = function() {
      const channelData = new Float32Array(arguments[1]);
      for (let i = 0; i < channelData.length; i++) {
        channelData[i] += noise.audioNoise;
      }
      return originalCopyFromChannel.apply(this, [channelData, ...Array.prototype.slice.call(arguments, 1)]);
    };
    const originalCopyToChannel = AudioBuffer.prototype.copyToChannel;
    AudioBuffer.prototype.copyToChannel = function() {
      const channelData = arguments[0];
      for (let i = 0; i < channelData.length; i++) {
        channelData[i] += noise.audioNoise;
      }
      return originalCopyToChannel.apply(this, arguments);
    };

    // WebGL Noisify
    const originalGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function() {
      const value = originalGetParameter.apply(this, arguments);
      if (typeof value === 'number') {
        return value + noise.webglNoise;
      }
      return value;
    };

    // ClientRects Noisify
    const originalGetBoundingClientRect = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function() {
      const rect = originalGetBoundingClientRect.apply(this, arguments);
      const deltaX = noise.clientRectsNoise.deltaX;
      const deltaY = noise.clientRectsNoise.deltaY;
      return {
        x: rect.x + deltaX, y: rect.y + deltaY,
        width: rect.width + deltaX, height: rect.height + deltaY,
        top: rect.top + deltaY, right: rect.right + deltaX,
        bottom: rect.bottom + deltaY, left: rect.left + deltaX
      };
    };
  })();
`;

// ── Random click simulator ──────────────────────────────────────────────────
const performRandomClicks = async (page) => {
  for (let i = 0; i < 1; i++) {
    const width = await page.evaluate(() => window.innerWidth);
    const height = await page.evaluate(() => window.innerHeight);
    const x = generateRandomNumber(0, width);
    const y = generateRandomNumber(0, height);
    await page.mouse.click(x, y);
    await page.waitForTimeout(generateRandomNumber(2000, 3000));
  }
};

// ── Discord screenshot sender ───────────────────────────────────────────────
const sendToDiscord = async (screenshotBuffer, meta) => {
  const webhookUrl = process.env.DISCORD_WEBHOOK_URL;
  if (!webhookUrl) {
    console.log("[Discord] No DISCORD_WEBHOOK_URL set, skipping.");
    return;
  }
  try {
    const { FormData, Blob } = await import("node:buffer").then(() => globalThis);
    const form = new FormData();
    form.append(
      "payload_json",
      JSON.stringify({
        embeds: [
          {
            title: `Screenshot — ${meta.url}`,
            color: 0x5865f2,
            fields: [
              { name: "URL", value: meta.url, inline: true },
              { name: "Timezone", value: meta.timezone, inline: true },
              { name: "Device", value: meta.device, inline: true },
              { name: "IP", value: String(meta.proxyIP), inline: true },
            ],
            image: { url: "attachment://screenshot.png" },
            footer: { text: new Date().toUTCString() },
          },
        ],
      }),
    );
    form.append(
      "files[0]",
      new Blob([screenshotBuffer], { type: "image/png" }),
      "screenshot.png",
    );
    const res = await fetch(webhookUrl, { method: "POST", body: form });
    if (res.ok) {
      console.log("[Discord] Screenshot sent.");
    } else {
      console.log(`[Discord] Failed: ${res.status}`);
    }
  } catch (err) {
    console.log("[Discord] Error:", err.message);
  }
};

// ── Type like a human (random delays per keystroke) ─────────────────────────
const humanType = async (page, selector, text) => {
  await page.click(selector);
  await page.waitForTimeout(generateRandomNumber(300, 800));
  for (const char of text) {
    await page.keyboard.type(char, { delay: generateRandomNumber(50, 200) });
  }
};

// ── Core: open browser, visit URL, behave like a human ──────────────────────
const visitUrl = async (url, myTor, proxyIP) => {
  const userPreference = weightedRandom(preferences);

  const timezone = await checkTz(myTor.socksPort);
  if (timezone == undefined) {
    console.log("[-] Undefined timezone, skipping");
    return false;
  }

  const server = `socks5://127.0.0.1:${myTor.socksPort}`;
  const browser = await chromium.launch({
    headless: false,
    proxy: { server },
  });

  const context = await newInjectedContext(browser, {
    fingerprintOptions: {
      devices: [userPreference.device],
      browsers: [userPreference.browser],
      operatingSystems: [userPreference.os],
      mockWebRTC: true,
    },
    newContextOptions: {
      timezoneId: timezone || "America/New_York",
    },
  });

  try {
    const noise = generateNoise();
    const page = await context.newPage();
    await page.addInitScript(noisifyScript(noise));

    const displayUrl = searchQuery ? `google.com/search?q=${encodeURIComponent(searchQuery)}` : url;
    console.log(
      `[VISIT] ${displayUrl} | TZ: ${timezone} | Device: ${userPreference.device} | IP: ${proxyIP} | SOCKS: ${myTor.socksPort}`
    );

    await page.goto(url, { waitUntil: "load" });
    await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});

    // If search query is set, type it into Google and search
    if (searchQuery) {
      console.log(`[SEARCH] Typing: "${searchQuery}"`);

      // Wait for search box to appear
      const searchBox = 'textarea[name="q"], input[name="q"]';
      await page.waitForSelector(searchBox, { timeout: 10000 }).catch(() => {});

      // Type like a human
      await humanType(page, searchBox, searchQuery);
      await page.waitForTimeout(generateRandomNumber(500, 1500));

      // Press Enter to search
      await page.keyboard.press("Enter");
      console.log("[SEARCH] Submitted, waiting for results...");
      await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
      await page.waitForTimeout(generateRandomNumber(2000, 5000));

      // Scroll down a bit like a human browsing results
      await page.mouse.wheel(0, generateRandomNumber(200, 600));
      await page.waitForTimeout(generateRandomNumber(1000, 3000));
    }

    // Simulate human reading time: 5-15s
    const initialWait = generateRandomNumber(5000, 15000);
    console.log(`[WAIT] Reading for ${Math.round(initialWait / 1000)}s...`);
    await page.waitForTimeout(initialWait).catch(() => {});

    await performRandomClicks(page);

    // Dwell: 15-60s
    const dwellTime = generateRandomNumber(15000, 60000);
    console.log(`[DWELL] Staying for ${Math.round(dwellTime / 1000)}s...`);
    await page.waitForTimeout(dwellTime).catch(() => {});

    // Screenshot
    if (enableScreenshot) {
      const screenshot = await page.screenshot({ fullPage: false }).catch(() => null);
      if (screenshot) {
        await sendToDiscord(screenshot, {
          url,
          timezone,
          device: userPreference.device,
          proxyIP,
        });
      }
    }

    // Rotate Tor circuit
    await renewTorSession(myTor);
    console.log("[OK] Visit complete, Tor session renewed");
    return true;
  } catch (error) {
    console.error("[-] Error:", error.message);
  } finally {
    await context.close();
    await browser.close();
  }
};

// ── Main loop ───────────────────────────────────────────────────────────────
const run = async () => {
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("  Undetected Google Visitor via Tor");
  if (searchQuery) {
    console.log(`  Search: "${searchQuery}"`);
  } else {
    console.log(`  Target: ${targetUrl}`);
  }
  console.log(`  Threads: ${threads} | Rotations: ${rotations} | Screenshot: ${enableScreenshot}`);
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  for (let r = 0; r < rotations; r++) {
    console.log(`\n[ROTATION ${r + 1}/${rotations}]`);

    const tasks = Array.from({ length: threads }).map(async (_, i) => {
      const myTor = torInstances[i % torInstances.length];
      const proxyIP = await checkTorIP(myTor.socksPort);
      console.log(`[THREAD ${i + 1}] SOCKS: ${myTor.socksPort} | IP: ${proxyIP}`);
      return visitUrl(targetUrl, myTor, proxyIP);
    });

    await Promise.all(tasks);
  }

  console.log("\n[DONE] All rotations complete.");
};

run();
