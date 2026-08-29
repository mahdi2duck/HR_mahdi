import { chromium } from "playwright";
import { newInjectedContext } from "fingerprint-injector";
import { checkTz, checkTorIP } from "./tor_traffic_tz.js";
import "dotenv/config";
import tr from "tor-request";
import fs from "fs/promises";

// ── Stealth traffic bot — no proxy, direct local network ──────────────────
// Usage:  node matrix_traffic.js work=<N>   → run a workflow
//         node matrix_traffic.js url=<URL>  → test mode, open any URL directly

const args = process.argv.slice(2);
let theworknum = null;
let testUrl = null;
let enableScreenshot = true; // default ON — pass screenshot=false to disable
let testThreads = 1; // default 1 thread in test mode — override with threads=N
let testRotations = 1; // default 1 rotation in test mode — override with rotation=N

args.forEach((arg) => {
  if (arg.startsWith("work=")) {
    theworknum = arg.split("=")[1].match(/\d+/)[0];
  }
  if (arg.startsWith("url=")) {
    testUrl = arg.slice(4); // everything after "url="
  }
  if (arg.startsWith("threads=")) {
    testThreads = parseInt(arg.split("=")[1], 10) || 1;
  }
  if (
    arg.startsWith("rotation=") ||
    arg.startsWith("rotations=") ||
    arg.startsWith("rot=")
  ) {
    testRotations = parseInt(arg.split("=")[1], 10) || 1;
  }
  if (arg.startsWith("screenshot=")) {
    enableScreenshot = arg.split("=")[1].toLowerCase() !== "false";
  }
});

// change this
//const endPoint = `http://localhost:3000`; // change this
// change this
const endPoint = "https://crap-app.pages.dev";
async function getNodeInfo() {
  try {
    const request = await fetch(`${endPoint}/threads.json`);
    console.log("Fetching node info...");
    const data = await request.json();
    return data;
  } catch (error) {
    console.log(error);
  }
}
// Simple IP tracking
const ipCounts = new Map();

// Save IP to simple text file
async function saveIP(ip) {
  // Update count in memory
  ipCounts.set(ip, (ipCounts.get(ip) || 0) + 1);

  // Write to file (format: IP COUNT)
  let lines = [];
  for (const [ip, count] of ipCounts.entries()) {
    lines.push(`${ip} ${count}`);
  }

  await fs.writeFile("tor_ips.txt", lines.join("\n"), "utf8");
  console.log(`IP: ${ip} - Count: ${ipCounts.get(ip)}`);
}

async function getCustomCountries() {
  try {
    const request = await fetch(`${endPoint}/countries.json`);
    console.log("Fetching custom countries...");
    const data = await request.json();
    return data;
  } catch (error) {
    console.log(error);
  }
}

function generateRandomNumber(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

const locations = [
  "se", // Sweden
  "ng", // Nigeria
  "cm", // Cameroon
  "ci", // Cote D'Ivoire
  "ua", // Ukraine
  "at", // Austria
  "at", // Austria
  "fr", // France
  "ca", // Canada
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "us", // United States
  "fr", // France
  "fr", // France
  "fr", // France
  "uk", // United Kingdom
  "au", // Australia
  "de", // Germany
  "jp", // Japan
  "sg", // Singapore
  "kr", // South Korea
  "it", // Italy
  "es", // Spain
  "in", // India
  "id", // Indonesia
  "ph", // Philippines
  "th", // Thailand
  "my", // Malaysia
  "eg", // Egypt
  "tr", // Turkey
  "pk", // Pakistan (English speakers, strong internet growth)
  "bd", // Bangladesh (growing internet users, relevance to global content)
  "mx", // Mexico (geographical proximity, U.S. ties)
  "lk", // Sri Lanka
  "ml", // Mali
  "bj", // Benin
  "ug", // Uganda
  "mm", // Myanmar
  "no", // Norway
  "pf", // French Polynesia
  "np", // Nepal
  "bf", // Burkina Faso
  "cd", // Congo, The Democratic Republic of the
  "bi", // Burundi
  "gf", // French Guiana
  "cf", // Central African Republic
  "hk", // Hong Kong
  "cg", // Congo
];

// Function to select a random user preference
const weightedRandom = (weights) => {
  let totalWeight = weights.reduce((sum, weight) => sum + weight.weight, 0);
  let random = Math.random() * totalWeight;
  for (let i = 0; i < weights.length; i++) {
    if (random < weights[i].weight) return weights[i].value;
    random -= weights[i].weight;
  }
};

// Preferences for user agents and devices
const preferences = [
  {
    value: { device: "desktop", os: "windows", browser: "chrome" },
    weight: 20,
  },

  {
    value: { device: "mobile", os: "android", browser: "chrome" },
    weight: 100,
  },
];

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
        results[i] += noise.audioNoise; // Smaller variation
      }
      return results;
    };

    const originalCopyFromChannel = AudioBuffer.prototype.copyFromChannel;
    AudioBuffer.prototype.copyFromChannel = function() {
      const channelData = new Float32Array(arguments[1]);
      for (let i = 0; i < channelData.length; i++) {
        channelData[i] += noise.audioNoise; // Smaller variation
      }
      return originalCopyFromChannel.apply(this, [channelData, ...Array.prototype.slice.call(arguments, 1)]);
    };

    const originalCopyToChannel = AudioBuffer.prototype.copyToChannel;
    AudioBuffer.prototype.copyToChannel = function() {
      const channelData = arguments[0];
      for (let i = 0; i < channelData.length; i++) {
        channelData[i] += noise.audioNoise; // Smaller variation
      }
      return originalCopyToChannel.apply(this, arguments);
    };

    // WebGL Noisify
    const originalGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function() {
      const value = originalGetParameter.apply(this, arguments);
      if (typeof value === 'number') {
        return value + noise.webglNoise; // Small random variation
      }
      return value;
    };

    // ClientRects Noisify
    const originalGetBoundingClientRect = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function() {
      const rect = originalGetBoundingClientRect.apply(this, arguments);
      const deltaX = noise.clientRectsNoise.deltaX; // Random shift between -1 and 1
      const deltaY = noise.clientRectsNoise.deltaY; // Random shift between -1 and 1
      return {
        x: rect.x + deltaX,
        y: rect.y + deltaY,
        width: rect.width + deltaX,
        height: rect.height + deltaY,
        top: rect.top + deltaY,
        right: rect.right + deltaX,
        bottom: rect.bottom + deltaY,
        left: rect.left + deltaX
      };
    };
  })();
`;

// Function to simulate random clicks on a page
const performRandomClicks = async (page, currentNode) => {
  for (let i = 0; i < 1; i++) {
    const width = await page.evaluate(() => window.innerWidth);
    const height = await page.evaluate(() => window.innerHeight);
    const x = generateRandomNumber(0, width);
    const y = generateRandomNumber(0, height);
    await page.mouse.click(x, y);
    await page.waitForTimeout(generateRandomNumber(2000, 3000));
  }
};

const blockResources = async (page) => {
  await page.route("**/*", (route) => {
    const resourceType = route.request().resourceType();
    if (["image", "stylesheet", "media"].includes(resourceType)) {
      route.abort();
    } else {
      route.continue();
    }
  });
};

// ── Discord screenshot sender ────────────────────────────────────────────────
const sendToDiscord = async (screenshotBuffer, meta) => {
  const webhookUrl = process.env.DISCORD_WEBHOOK_URL;
  if (!webhookUrl) {
    console.log("[Discord] No DISCORD_WEBHOOK_URL set, skipping.");
    return;
  }
  try {
    const { FormData, Blob } = await import("node:buffer").then(
      () => globalThis,
    );
    const form = new FormData();
    form.append(
      "payload_json",
      JSON.stringify({
        embeds: [
          {
            title: `📸 Screenshot — Work #${meta.work}`,
            color: 0x5865f2,
            fields: [
              { name: "🌐 Site", value: meta.link, inline: true },
              { name: "🕐 Timezone", value: meta.timezone, inline: true },
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
    } else {
      console.log(`[Discord] Failed: ${res.status} ${res.statusText}`);
    }
  } catch (err) {
    console.log("[Discord] Error sending screenshot:", err.message);
  }
};
const torInstances = [
  { socksPort: 9050, controlPort: 9051 }, // Instance 1
  { socksPort: 9150, controlPort: 9151 }, // Instance 2
  { socksPort: 9250, controlPort: 9251 }, // Instance 3
];

const renewTorSession = (myTor) => {
  return new Promise((resolve, reject) => {
    tr.TorControlPort.port = myTor.controlPort;
    tr.TorControlPort.password = "mahdi2019";
    tr.newTorSession((err) => {
      if (err) return reject(err);
      // console.log("New session renewed");
      resolve();
    });
  });
};

const OpenBrowser = async (currentNode, views, myTor, proxyIP) => {
  const userPreference = weightedRandom(preferences);
  const timezone = await checkTz(myTor.socksPort);
  if (timezone == undefined) {
    console.log("undefined timezone, skipping this bot");
    return false;
  }
  const server = `socks5://127.0.0.1:${myTor.socksPort}`;
  const browser = await chromium.launch({
    headless: false,
    proxy: {
      server: server,
    },
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
    // ──  add media blockers ───────────────────────────────────────
    // ──  await blockResources(page); ───────────────────────────────────────
    await page.addInitScript(noisifyScript(noise));
    console.log(
      `worker -> ${theworknum}| views -> ${views.views} | website -> ${currentNode.link} | custom countries -> ${currentNode.custom_location} | threads -> ${currentNode.bots} | Browser view from -> ${timezone} | userPreference -> ${userPreference.device}`,
    );
    await page.goto(currentNode.link, { waitUntil: "load" });
    // ── Wait for network to settle after page load ───────────────────────────────────────
    await page
      .waitForLoadState("networkidle", { timeout: 30000 })
      .catch(() => {});

    // ── Random initial wait (simulate human reading time: 5-15 seconds) ───────────────────────────────────────
    const initialWait = generateRandomNumber(5000, 15000);
    await page.waitForTimeout(initialWait).catch(() => {});
    await performRandomClicks(page);
    const dwellTime = generateRandomNumber(15000, 60000);
    await page.waitForTimeout(dwellTime).catch(() => {});

    // ── Screenshot + Discord (controlled by screenshot= flag) ───────────────
    if (enableScreenshot) {
      const screenshot = await page
        .screenshot({ fullPage: false })
        .catch(() => null);
      if (screenshot) {
        await sendToDiscord(screenshot, {
          work: theworknum || "Test mode",
          link: currentNode.link,
          timezone: timezone,
          device: userPreference.device,
          views: views?.views ?? 0,
          proxyIP: proxyIP,
        });
      }
    } else {
      console.log("[Screenshot] Skipped (screenshot=false)");
    }

    // ── change tor proxy ───────────────────────────────────────
    await renewTorSession(myTor);
    return true;
  } catch (error) {
    console.log(error);
  } finally {
    await context.close();
    await browser.close();
  }
};

const tasksPoll = async (currentNode, countries, views) => {
  const botCount = Number(currentNode.bots) || 1;

  const tasks = Array.from({
    length: botCount || 2,
  }).map(async (_, i) => {
    const myTor = torInstances[i % torInstances.length];
    const proxyIP = await checkTorIP(myTor.socksPort);
    console.log(
      `[Bot] Control Port for bot ${i} with ${myTor.controlPort} | IP: ${proxyIP}`,
    );
    return OpenBrowser(currentNode, views, myTor, proxyIP);
  });

  await Promise.all(tasks);
};

const RunTasks = async () => {
  const nodes = await getNodeInfo();
  const viewLog = [];
  const currentNode = nodes["work_" + theworknum];
  const keys = Object.keys(currentNode);

  keys.map((key) => {
    viewLog.push({ key: theworknum, node: currentNode[key], views: 0 });
  });

  for (let i = 0; i < 345535345; i++) {
    const countries = await getCustomCountries();
    const nodes = await getNodeInfo();

    if (nodes === undefined || nodes.length < 0) {
      console.log("No nodes found or error fetching nodes.");
      return;
    }
    const currentNode = nodes["work_" + theworknum];
    const keys = Object.keys(currentNode);

    const tasks = keys.map((key) => {
      viewLog.map((item) =>
        item.node.link === currentNode[key].link
          ? (item.views += currentNode[key].bots)
          : item,
      );
      // Call tasksPoll for each node
      return tasksPoll(
        currentNode[key],
        countries,
        viewLog.find((item) => item.node.link === currentNode[key].link),
      );
    });

    console.log(
      `Running tasks for workflow ${theworknum}, nodes ${
        keys.length
      }, iteration ${i + 1}`,
    );
    await Promise.all(tasks);
  }
};

const RunTest = async () => {
  console.log(
    `[TEST MODE] Opening: ${testUrl} | threads: ${testThreads} | rotations: ${testRotations}`,
  );
  const fakeNode = { link: testUrl, custom_location: false, bots: testThreads };
  const fakeViews = { views: 0 };

  for (let r = 0; r < testRotations; r++) {
    console.log(`\n[TEST] Starting rotation ${r + 1}/${testRotations}`);
    // Spin up testThreads bots in parallel, round-robin across tor instances
    const tasks = Array.from({ length: testThreads || 1 }).map(async (_, i) => {
      const myTor = torInstances[i % torInstances.length];
      const proxyIP = await checkTorIP(myTor.socksPort);
      console.log(
        `[TEST] Thread ${i + 1}/${testThreads} → SOCKS ${myTor.socksPort} | Control ${myTor.controlPort} | IP: ${proxyIP}`,
      );
      return OpenBrowser(fakeNode, fakeViews, myTor, proxyIP);
    });

    await Promise.all(tasks);
  }
};

// ── Entry point ──────────────────────────────────────────────────────────────
if (testUrl) {
  RunTest();
} else {
  RunTasks();
}
