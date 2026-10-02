import { createServer as createHTTPServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { ServiceError, TwitchService, validateChannel } from './twitch.js';

const MAX_BODY_BYTES = 16 * 1024;

function sendJSON(response, status, body) {
  const data = JSON.stringify(body);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(data),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  response.end(data);
}

function bearerMatches(request, expectedToken) {
  if (!expectedToken) return true;
  const supplied = request.headers.authorization?.match(/^Bearer (.+)$/i)?.[1];
  if (!supplied) return false;
  const suppliedBytes = Buffer.from(supplied);
  const expectedBytes = Buffer.from(expectedToken);
  return suppliedBytes.length === expectedBytes.length
    && timingSafeEqual(suppliedBytes, expectedBytes);
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw new ServiceError(413, 'body_too_large', 'Request body is too large.');
    }
    chunks.push(chunk);
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new ServiceError(400, 'invalid_json', 'Request body must be valid JSON.');
  }
}

export function createServer({ twitch, apiBearerToken = '' }) {
  return createHTTPServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');

      if (request.method === 'GET' && url.pathname === '/healthz') {
        return sendJSON(response, 200, { status: 'ok' });
      }

      if (!bearerMatches(request, apiBearerToken)) {
        return sendJSON(response, 401, {
          error: { code: 'unauthorized', message: 'A valid bearer token is required.' },
        });
      }

      if (request.method === 'POST' && url.pathname === '/v1/playback') {
        if (!request.headers['content-type']?.toLowerCase().includes('application/json')) {
          throw new ServiceError(415, 'unsupported_media_type', 'Content-Type must be application/json.');
        }

        const body = await readJSON(request);
        if (!validateChannel(body?.channel)) {
          throw new ServiceError(400, 'invalid_channel', 'Channel must be a Twitch login name (1–25 letters, numbers, or underscores).');
        }

        const channel = body.channel.toLowerCase();
        const status = await twitch.getStreamStatus(channel);
        if (!status.isLive) {
          throw new ServiceError(404, 'stream_offline', 'That Twitch channel is not live.');
        }

        const playback = await twitch.getPlaybackURL(channel);
        return sendJSON(response, 200, { isLive: true, ...playback });
      }

      const statusMatch = url.pathname.match(/^\/v1\/streams\/([^/]+)$/);
      if (request.method === 'GET' && statusMatch) {
        let channel;
        try {
          channel = decodeURIComponent(statusMatch[1]);
        } catch {
          throw new ServiceError(400, 'invalid_channel', 'Channel name is invalid.');
        }
        if (!validateChannel(channel)) {
          throw new ServiceError(400, 'invalid_channel', 'Channel must be a Twitch login name (1–25 letters, numbers, or underscores).');
        }
        return sendJSON(response, 200, await twitch.getStreamStatus(channel.toLowerCase()));
      }

      sendJSON(response, 404, { error: { code: 'not_found', message: 'Route not found.' } });
    } catch (error) {
      if (response.headersSent) {
        response.destroy();
        return;
      }

      const serviceError = error instanceof ServiceError
        ? error
        : new ServiceError(500, 'internal_error', 'An unexpected server error occurred.');
      if (serviceError.status >= 500) {
        console.error(`[backend] ${serviceError.code}: ${serviceError.message}`);
      }
      sendJSON(response, serviceError.status, {
        error: { code: serviceError.code, message: serviceError.message },
      });
    }
  });
}

const isDirectRun = process.argv[1]
  && fileURLToPath(import.meta.url) === process.argv[1];

if (isDirectRun) {
  let twitch;
  try {
    twitch = new TwitchService({
      clientId: process.env.TWITCH_CLIENT_ID,
      clientSecret: process.env.TWITCH_CLIENT_SECRET,
      streamlinkBin: process.env.STREAMLINK_BIN || 'streamlink',
    });
  } catch (error) {
    console.error(`[backend] ${error.message}`);
    process.exit(1);
  }

  const port = Number.parseInt(process.env.PORT || '3000', 10);
  const host = process.env.HOST || '0.0.0.0';
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('[backend] PORT must be a valid TCP port.');
    process.exit(1);
  }

  const server = createServer({ twitch, apiBearerToken: process.env.API_BEARER_TOKEN || '' });
  server.listen(port, host, () => {
    console.log(`[backend] listening on http://${host}:${port}`);
  });
}
