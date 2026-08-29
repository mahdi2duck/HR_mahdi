import axios from "axios";
import { SocksProxyAgent } from "socks-proxy-agent";
import "dotenv/config";

export const checkTz = async (socksPort) => {
  // Create SOCKS5 proxy agent for Tor
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
        family: 4, // Force IPv4
      },
    );
    const ipDetails = { timezone: response.data.trim() };
    return ipDetails?.timezone || undefined;
  } catch (error) {
    console.error("Error fetching timezone:", error.message);
    return undefined;
  }
};

export const checkTorIP = async (socksPort) => {
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
      family: 4, // Force IPv4
    });
    return response.data.origin;
  } catch (error) {
    return "Offline/Error";
  }
};
