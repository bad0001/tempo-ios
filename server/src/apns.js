// APNs 推送 — 用 .p8 token-based auth (而不是老的 cert-based).
import apn from 'apn';
import { readFileSync } from 'node:fs';
import { EventEmitter } from 'node:events';

const KEY_PATH = process.env.APNS_KEY_PATH;
const KEY_ID = process.env.APNS_KEY_ID;
const TEAM_ID = process.env.APNS_TEAM_ID;
const TOPIC = process.env.APNS_TOPIC || 'com.ayipocket.tempo';
const PRODUCTION = (process.env.APNS_PRODUCTION || 'false').toLowerCase() === 'true';

// node-apn 在重连/wakeup 时会给底层 Connection 累加 listener,默认上限 10 时会触发
// MaxListenersExceededWarning。30 对长跑足够,真有 leak 也能在日志里看到
EventEmitter.defaultMaxListeners = 30;

let provider = null;
let providerInitFailed = false;

function getProvider() {
  if (provider) return provider;
  if (providerInitFailed) return null;   // 已经知道失败,不要每次 sendAlert 都同步重读
  let keyContent;
  try {
    keyContent = readFileSync(KEY_PATH, 'utf8');
  } catch (e) {
    console.error('[apns] CRITICAL: cannot read APNs key at', KEY_PATH, '—', e.message);
    providerInitFailed = true;
    return null;
  }
  try {
    provider = new apn.Provider({
      token: { key: keyContent, keyId: KEY_ID, teamId: TEAM_ID },
      production: PRODUCTION,
    });
    if (typeof provider.setMaxListeners === 'function') {
      provider.setMaxListeners(30);
    }
    return provider;
  } catch (e) {
    console.error('[apns] CRITICAL: failed to construct provider:', e.message);
    providerInitFailed = true;
    return null;
  }
}

/// 给设备 token 列表发同一条 alert.
export async function sendAlert({ tokens, title, body, data, category }) {
  if (!tokens || tokens.length === 0) return { sent: 0 };
  const p = getProvider();
  if (!p) return { sent: 0, error: 'apns key unavailable' };
  const note = new apn.Notification();
  note.alert = { title, body };
  note.topic = TOPIC;
  note.sound = 'default';
  if (category) note.category = category;
  note.payload = data || {};
  note.expiry = Math.floor(Date.now() / 1000) + 3600;  // 1h
  const result = await p.send(note, tokens);
  return {
    sent: result.sent.length,
    failed: result.failed.map(f => ({ device: f.device, status: f.status, response: f.response })),
  };
}

/// silent push — 用 content-available 触发 client 后台 fetch
export async function sendSilent({ tokens, data }) {
  if (!tokens || tokens.length === 0) return { sent: 0 };
  const p = getProvider();
  if (!p) return { sent: 0, error: 'apns key unavailable' };
  const note = new apn.Notification();
  note.contentAvailable = 1;
  note.priority = 5;
  note.topic = TOPIC;
  note.payload = data || {};
  note.expiry = Math.floor(Date.now() / 1000) + 3600;
  const result = await p.send(note, tokens);
  return { sent: result.sent.length, failed: result.failed.length };
}

export function shutdownApns() {
  if (provider) {
    if (typeof provider.removeAllListeners === 'function') {
      provider.removeAllListeners();
    }
    provider.shutdown();
    provider = null;
  }
}
