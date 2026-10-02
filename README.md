# Glitch-For-Twitch
A Twitch client for watchOS.

## Backend

The watch app uses a small Node.js backend for Twitch live-status lookup and playback URL resolution. See [`backend/README.md`](backend/README.md) for requirements, setup, and API details.

Twitch does not expose HLS playback URLs through its official Helix API. The backend uses Streamlink to resolve playback URLs, so that integration may need updates if Twitch changes its playback behavior. Keep Twitch API credentials on the backend, never in the app.
