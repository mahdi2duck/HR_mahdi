// No proxy used — fetch timezone directly via local network
export const checkTz = async () => {
  try {
    const response = await fetch(
      "https://worker-purple-wind-1de7.idrissimahdi2020.workers.dev",
      {
        signal: AbortSignal.timeout(10000),
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        },
      }
    );
    const text = await response.text();
    return text.trim() || undefined;
  } catch (error) {
    console.error("Error fetching timezone:", error.message);
    return undefined;
  }
};