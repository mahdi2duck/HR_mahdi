import axios from "axios";
import { HttpsProxyAgent } from "https-proxy-agent";
import "dotenv/config";

export const checkTz = async (username) => {
  if (!process.env.proxy_server) {
    console.error("CRITICAL: Missing proxy_server in .env");
    return undefined;
  }
  if (!process.env.proxy_password) {
    console.error("CRITICAL: Missing proxy_password in .env");
    return undefined;
  }
  const proxyHost = process.env.proxy_server;
  const proxyUsername = username;
  const proxyPassword = process.env.proxy_password;

  // Properly formatted proxy URL
  const proxyUrl = `http://${proxyUsername}:${proxyPassword}@${proxyHost}`;

  const proxyAgent = new HttpsProxyAgent(proxyUrl);
  try {
    const response = await axios.get(
      "https://worker-purple-wind-1de7.idrissimahdi2020.workers.dev",
      {
        httpsAgent: proxyAgent,
        timeout: 10000,
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        },
      }
    );
    const ipDetails = { timezone: response.data.trim() };
    return ipDetails?.timezone || undefined;
  } catch (error) {
    console.error("Error fetching timezone:", error.message);
    return undefined;
  }
};