import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from '../src/server.js';
import { TwitchService } from '../src/twitch.js';

async function withServer(t, twitch, run, apiBearerToken = '') {
  const server = createServer({ twitch, apiBearerToken });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const address = server.address();
  await run(`http://127.0.0.1:${address.port}`);
}

test('health endpoint responds without Twitch credentials', async (t) => {
  await withServer(t, {}, async (baseURL) => {
    const response = await fetch(`${baseURL}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});

test('playback rejects malformed JSON and channel names before calling Twitch', async (t) => {
  const twitch = {
    async getStreamStatus() { assert.fail('Twitch must not be called for invalid requests'); },
    async getPlaybackURL() { assert.fail('resolver must not be called for invalid requests'); },
  };

  await withServer(t, twitch, async (baseURL) => {
    const malformed = await fetch(`${baseURL}/v1/playback`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{',
    });
    assert.equal(malformed.status, 400);
    assert.equal((await malformed.json()).error.code, 'invalid_json');

    const invalidChannel = await fetch(`${baseURL}/v1/playback`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ channel: 'not/a/channel' }),
    });
    assert.equal(invalidChannel.status, 400);
    assert.equal((await invalidChannel.json()).error.code, 'invalid_channel');
  });
});

test('playback returns the response shape expected by the watch app', async (t) => {
  const twitch = {
    async getStreamStatus(channel) {
      assert.equal(channel, 'test_channel');
      return { channel, isLive: true };
    },
    async getPlaybackURL() {
      return {
        playbackURL: 'https://usher.ttvnw.net/api/channel/hls/test_channel.m3u8',
        expiresAt: '2026-10-01T00:05:00Z',
        contentType: 'application/vnd.apple.mpegurl',
      };
    },
  };

  await withServer(t, twitch, async (baseURL) => {
    const response = await fetch(`${baseURL}/v1/playback`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ channel: 'Test_Channel' }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      isLive: true,
      playbackURL: 'https://usher.ttvnw.net/api/channel/hls/test_channel.m3u8',
      expiresAt: '2026-10-01T00:05:00Z',
      contentType: 'application/vnd.apple.mpegurl',
    });
  });
});

test('Twitch status timestamps use whole-second ISO-8601', async () => {
  const service = new TwitchService({
    clientId: 'client-id',
    clientSecret: 'client-secret',
    fetchImpl: async (url) => {
      if (String(url).includes('oauth2/token')) {
        return { ok: true, async json() { return { access_token: 'app-token', expires_in: 3600 }; } };
      }
      return {
        ok: true,
        async json() {
          return { data: [{ title: 'Live', game_name: 'Category', viewer_count: 5 }] };
        },
      };
    },
  });

  const status = await service.getStreamStatus('example');
  assert.equal(status.isLive, true);
  assert.match(status.checkedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
});

test('optional bearer token protects API routes', async (t) => {
  await withServer(t, {}, async (baseURL) => {
    const response = await fetch(`${baseURL}/v1/streams/channel`, {
      headers: { authorization: 'Bearer wrong' },
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.code, 'unauthorized');
  }, 'test-secret');
});
