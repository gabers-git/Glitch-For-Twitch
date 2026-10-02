# Backend

This service provides the JSON API used by the watch app. It uses Twitch's official Helix API to determine whether a channel is live, and invokes [Streamlink](https://streamlink.github.io/) to resolve a current HLS playback URL. Twitch's official Helix API does **not** provide HLS playback URLs; Streamlink's Twitch resolver depends on Twitch playback behavior that may change independently of this backend.

## Requirements

- Node.js 20 or newer
- Streamlink installed and available as `streamlink` on `PATH`
- A Twitch developer application (`TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET`)

Keep the Twitch client secret on the server. Do not put it in the watch app or commit it.

## Run locally

From this directory, set `TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET` in your shell or deployment environment (the `.env.example` file lists all supported variables), then run:

```sh
npm test
npm start
```

For example, in a shell:

```sh
export TWITCH_CLIENT_ID='your-client-id'
export TWITCH_CLIENT_SECRET='your-client-secret'
npm start
```

The server reads environment variables directly; it does not automatically load `.env`. The backend uses only Node built-ins, so `npm install` is not needed. Check `GET http://localhost:3000/healthz` for service health.

For a physical Apple Watch, `localhost` refers to the watch itself. The app is configured for `https://twitch-api.gaber.ca`. Enter a real Twitch login name in the watch app's channel field, then tap **Watch** or submit from the keyboard.

## Cloudflare Tunnel for `gaber.ca`

Keep the existing website hostname and add a separate public hostname for the backend:

1. Start the backend on the same machine as `cloudflared`, listening on localhost:

   ```sh
   export HOST=127.0.0.1
   export PORT=3000
   export TWITCH_CLIENT_ID='your-client-id'
   export TWITCH_CLIENT_SECRET='your-client-secret'
   npm start
   ```

2. In the Cloudflare Zero Trust dashboard, open **Networks → Tunnels**, select the tunnel already serving your website, and add a **Public Hostname** (sometimes labeled **Published application route**):
   - Subdomain: `twitch-api`
   - Domain: `gaber.ca`
   - Service type: `HTTP`
   - Service URL: `localhost:3000` (or `http://localhost:3000`, depending on the dashboard form)

   Cloudflare routes `https://twitch-api.gaber.ca` through the existing tunnel to the backend. This adds a hostname; it should not replace your website's existing `gaber.ca` or `www` route. If `cloudflared` is on a different machine from the backend, use the backend machine's private LAN address instead of `localhost`, and allow port 3000 only from that private network.

3. Make sure the API hostname does not require an interactive Cloudflare Access browser login: the watch app's URLSession request cannot complete that login flow. Add Cloudflare rate limiting (and stronger API authentication before wider public use); do not expose port 3000 directly to the internet.

4. Verify the route from outside your server:

   ```sh
   curl https://twitch-api.gaber.ca/healthz
   ```

   It should return `{"status":"ok"}`. The app is already configured to use this hostname. Enter an actual Twitch login in the channel field and tap **Watch**.

## API

### `POST /v1/playback`

Request:

```json
{"channel":"test_channel"}
```

If the channel is live, the response matches the app's `PlaybackResponse`:

```json
{
  "isLive": true,
  "playbackURL": "https://usher.ttvnw.net/...m3u8",
  "expiresAt": "2026-10-01T12:05:00Z",
  "contentType": "application/vnd.apple.mpegurl"
}
```

`expiresAt` is a conservative five-minute estimate because Streamlink does not expose a reliable expiry timestamp for every resolved manifest. Each request resolves a fresh URL. Offline channels return `404` with `error.code` set to `stream_offline`.

### `GET /v1/streams/:channel`

Returns the `StreamStatusResponse` shape used by the app's networking models:

```json
{
  "channel":"test_channel",
  "isLive":true,
  "title":"Stream title",
  "category":"Just Chatting",
  "viewerCount":123,
  "checkedAt":"2026-10-01T12:00:00Z"
}
```

### Errors

Errors are returned as `{ "error": { "code": "...", "message": "..." } }`. Routes reject invalid channel names; playback URLs are only accepted over HTTPS from Twitch's `ttvnw.net` CDN.

## Deployment notes

- Configure `HOST`, `PORT`, `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET`, and optionally `STREAMLINK_BIN` through the deployment environment.
- `API_BEARER_TOKEN` can protect the API for private testing. When set, callers need an `Authorization: Bearer ...` header. Do not ship a shared backend secret inside a public app; production user authentication/rate limiting should be added at the service boundary instead.
- Put the service behind HTTPS and a reverse proxy with request rate limits before exposing it publicly.
- The backend returns Twitch CDN URLs to the app; it does not relay video data. The watch must be able to reach Twitch's CDN directly.
