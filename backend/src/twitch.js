import { spawn } from 'node:child_process';

const TWITCH_API = 'https://api.twitch.tv/helix';
const TOKEN_URL = 'https://id.twitch.tv/oauth2/token';
const FETCH_TIMEOUT_MS = 8_000;
const STREAMLINK_TIMEOUT_MS = 15_000;
const PLAYBACK_URL_TTL_MS = 5 * 60 * 1000;

function iso8601Date(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export class ServiceError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = 'ServiceError';
    this.status = status;
    this.code = code;
  }
}

export function validateChannel(value) {
  return typeof value === 'string'
    && /^[a-zA-Z0-9_]{1,25}$/.test(value);
}

function requireHttpsTwitchPlaybackURL(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new ServiceError(502, 'invalid_playback_url', 'The playback resolver returned an invalid URL.');
  }

  const host = url.hostname.toLowerCase();
  const isTwitchCDN = host === 'ttvnw.net' || host.endsWith('.ttvnw.net');
  if (url.protocol !== 'https:' || !isTwitchCDN) {
    throw new ServiceError(502, 'invalid_playback_url', 'The playback resolver returned an unexpected URL.');
  }

  return url.toString();
}

export class TwitchService {
  constructor({ clientId, clientSecret, streamlinkBin = 'streamlink', fetchImpl = fetch }) {
    if (!clientId || !clientSecret) {
      throw new Error('TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET are required.');
    }
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.streamlinkBin = streamlinkBin;
    this.fetch = fetchImpl;
    this.appToken = null;
    this.tokenExpiresAt = 0;
  }

  async getAppToken() {
    if (this.appToken && Date.now() < this.tokenExpiresAt - 60_000) {
      return this.appToken;
    }

    let response;
    try {
      response = await this.fetch(TOKEN_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: this.clientId,
          client_secret: this.clientSecret,
          grant_type: 'client_credentials',
        }),
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
    } catch {
      throw new ServiceError(502, 'twitch_unavailable', 'Could not connect to Twitch authentication.');
    }

    if (!response.ok) {
      throw new ServiceError(502, 'twitch_auth_failed', 'Twitch authentication failed. Check the server credentials.');
    }

    let payload;
    try {
      payload = await response.json();
    } catch {
      throw new ServiceError(502, 'twitch_auth_failed', 'Twitch returned an unreadable authentication response.');
    }

    if (typeof payload.access_token !== 'string' || !Number.isFinite(payload.expires_in)) {
      throw new ServiceError(502, 'twitch_auth_failed', 'Twitch returned an invalid authentication response.');
    }

    this.appToken = payload.access_token;
    this.tokenExpiresAt = Date.now() + payload.expires_in * 1000;
    return this.appToken;
  }

  async getStreamStatus(channel) {
    const accessToken = await this.getAppToken();
    const endpoint = new URL(`${TWITCH_API}/streams`);
    endpoint.searchParams.set('user_login', channel.toLowerCase());

    let response;
    try {
      response = await this.fetch(endpoint, {
        headers: {
          'client-id': this.clientId,
          authorization: `Bearer ${accessToken}`,
        },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
    } catch {
      throw new ServiceError(502, 'twitch_unavailable', 'Could not connect to Twitch.');
    }

    if (!response.ok) {
      throw new ServiceError(502, 'twitch_api_failed', 'Twitch stream status lookup failed.');
    }

    let payload;
    try {
      payload = await response.json();
    } catch {
      throw new ServiceError(502, 'twitch_api_failed', 'Twitch returned an unreadable stream status response.');
    }

    const stream = payload.data?.[0];
    return {
      channel: channel.toLowerCase(),
      isLive: Boolean(stream),
      title: stream?.title ?? null,
      category: stream?.game_name ?? null,
      viewerCount: Number.isInteger(stream?.viewer_count) ? stream.viewer_count : null,
      checkedAt: iso8601Date(new Date()),
    };
  }

  async getPlaybackURL(channel) {
    const source = `https://www.twitch.tv/${channel.toLowerCase()}`;
    const rawURL = await new Promise((resolve, reject) => {
      const child = spawn(this.streamlinkBin, ['--stream-url', source, 'best'], {
        stdio: ['ignore', 'pipe', 'pipe'],
        shell: false,
      });
      let stdout = '';
      let stderr = '';
      let settled = false;

      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        if (error) reject(error);
        else resolve(value);
      };

      const timeout = setTimeout(() => {
        child.kill('SIGKILL');
        finish(new ServiceError(504, 'playback_timeout', 'Twitch playback resolution timed out.'));
      }, STREAMLINK_TIMEOUT_MS);

      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', (chunk) => {
        stdout += chunk;
        if (stdout.length > 64_000) {
          child.kill('SIGKILL');
          finish(new ServiceError(502, 'playback_resolver_failed', 'The playback resolver returned too much data.'));
        }
      });
      child.stderr.on('data', (chunk) => {
        stderr += chunk;
        if (stderr.length > 8_000) stderr = stderr.slice(-8_000);
      });
      child.on('error', (error) => {
        if (error.code === 'ENOENT') {
          finish(new ServiceError(503, 'playback_resolver_missing', 'Streamlink is not installed or STREAMLINK_BIN is incorrect.'));
        } else {
          finish(new ServiceError(502, 'playback_resolver_failed', 'Could not start the playback resolver.'));
        }
      });
      child.on('close', (code) => {
        const output = stdout.trim();
        if (code !== 0 || !output) {
          finish(new ServiceError(502, 'playback_resolver_failed', 'Could not resolve a Twitch playback URL.'));
        } else {
          finish(null, output.split(/\r?\n/).at(-1));
        }
      });
    });

    return {
      playbackURL: requireHttpsTwitchPlaybackURL(rawURL),
      expiresAt: iso8601Date(new Date(Date.now() + PLAYBACK_URL_TTL_MS)),
      contentType: 'application/vnd.apple.mpegurl',
    };
  }
}
