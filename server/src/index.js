import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { nanoid } from 'nanoid';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// version 从 package.json 读,QA 用 /health 验是否部署生效
const __dirname = dirname(fileURLToPath(import.meta.url));
let API_VERSION = 'unknown';
try {
  const pkg = JSON.parse(readFileSync(join(__dirname, '..', 'package.json'), 'utf8'));
  API_VERSION = pkg.version || 'unknown';
} catch (e) {
  console.error('[health] could not read package.json version:', e.message);
}
const STARTED_AT = Date.now();
const PUBLIC_DIR = join(__dirname, '..', 'public');
const PRIVACY_PAGE = readFileSync(join(PUBLIC_DIR, 'privacy.html'), 'utf8');
const TERMS_PAGE = readFileSync(join(PUBLIC_DIR, 'terms.html'), 'utf8');
const SUPPORT_PAGE = readFileSync(join(PUBLIC_DIR, 'support.html'), 'utf8');

import {
  upsertUser, getUser, findUserByEmailHash, findUserByPublicId,
  upsertDevice, getDevicesForUser, deleteDevice,
  createInvite, findInviteByCode, getInboxInvites, acceptInvite,
  createFriendRequest, getInboxRequests, getOutgoingRequests,
  getFriendRequest, actOnFriendRequest, cancelOutgoingFriendRequest,
  recordFriendship, deleteFriendship, getFriendsForUser,
  setFriendMute, isFriendMuted,
  createCareEvent, getCareEvent, getInboxCareEvents, getCareEventTimeline,
  markCareEventsRead, deleteCareEvent,
  upsertStressSnapshot, deleteStressSnapshot, getFriendStressSnapshots,
  countUserBottlesSince, createStressBottle, getSeaStressBottles, getMyStressBottles,
  getStressBottleForUser, replyToStressBottle, createModerationReport,
  getBottleReplyForOwner, hideBottleReplyForOwner,
  blockUser, deleteStressBottle, listModerationReports, resolveModerationReport,
  setStressBottleStatus,
  deleteUser, areFriends, pruneExpiredRequests,
  // Phase 2:
  appendStressHistory, getStressHistory,
  appendHRVSamples, getHRVHistory, deleteHRVSamples,
  createBreathingSession, createMeditationSession,
  getBreathingSessions, getMeditationSessions,
  upsertDailySummary, getDailySummary, aggregateYesterdayDailySummary,
  getSharePrefs, updateSharePrefs,
} from './db.js';
import {
  authenticateApple, hashEmail,
  issueSessionToken, verifySessionToken,
} from './auth.js';
import { sendAlert, sendSilent } from './apns.js';
import { rateLimit } from './rate-limit.js';

const app = new Hono();
const PORT = parseInt(process.env.PORT || '3002', 10);
const HOST = process.env.HOST || '127.0.0.1';
const INVITE_TTL_HOURS = parseInt(process.env.INVITE_TTL_HOURS || '72', 10);

app.use('*', logger());
app.use('*', cors());

// ---- Rate limits(在路由之前注册,要保证 IP-keyed 的限制不需要 session)
//   /v1/auth/apple      — 重 CPU(JWT 验签),IP 维度 10/min
//   /v1/friend-requests* — 防刷推送,user 维度 20/min(POST 创建 + accept/decline/cancel 共享)
//   /v1/users/by-public-id/* — 防暴力枚举 6 位 ID,user 维度 30/min
//   /v1/devices         — 防 token 写入轰炸,user 维度 10/min
//   兜底全局           — 任意 IP 200/min(防爬虫扫描)
app.use('*',                          rateLimit({ name: 'global',  windowMs: 60_000, max: 200, by: 'ip' }));
app.use('/v1/auth/apple',             rateLimit({ name: 'auth',    windowMs: 60_000, max: 10,  by: 'ip' }));
app.use('/v1/friend-requests',        rateLimit({ name: 'frcreate',windowMs: 60_000, max: 20,  by: 'user' }));
app.use('/v1/friend-requests/*',      rateLimit({ name: 'fract',   windowMs: 60_000, max: 60,  by: 'user' }));
app.use('/v1/users/by-public-id/*',   rateLimit({ name: 'lookup',  windowMs: 60_000, max: 30,  by: 'user' }));
app.use('/v1/devices',                rateLimit({ name: 'devices', windowMs: 60_000, max: 10,  by: 'user' }));
app.use('/v1/devices/*',              rateLimit({ name: 'devicesx',windowMs: 60_000, max: 20,  by: 'user' }));
app.use('/v1/invites',                rateLimit({ name: 'inv',     windowMs: 60_000, max: 20,  by: 'user' }));
app.use('/v1/care-events',            rateLimit({ name: 'care',    windowMs: 60_000, max: 60,  by: 'user' }));
app.use('/v1/care-events/*',          rateLimit({ name: 'carex',   windowMs: 60_000, max: 60,  by: 'user' }));
app.use('/v1/me/stress',              rateLimit({ name: 'stress',  windowMs: 60_000, max: 120, by: 'user' }));
app.use('/v1/bottles',                rateLimit({ name: 'bottle',  windowMs: 60_000, max: 20,  by: 'user' }));
app.use('/v1/bottles/*',              rateLimit({ name: 'bottlex', windowMs: 60_000, max: 60,  by: 'user' }));
// Phase 2:数据上传 endpoints
app.use('/v1/me/stress/history',      rateLimit({ name: 'shist',   windowMs: 60_000, max: 180, by: 'user' }));
app.use('/v1/me/hrv',                 rateLimit({ name: 'hrv',     windowMs: 60_000, max: 60,  by: 'user' }));
app.use('/v1/me/sessions',            rateLimit({ name: 'sess',    windowMs: 60_000, max: 30,  by: 'user' }));
app.use('/v1/me/daily-summary',       rateLimit({ name: 'dsum',    windowMs: 60_000, max: 30,  by: 'user' }));
app.use('/v1/me/share-prefs',         rateLimit({ name: 'pref',    windowMs: 60_000, max: 30,  by: 'user' }));
app.use('/v1/friends/*/stress/history',rateLimit({ name: 'fshist', windowMs: 60_000, max: 60,  by: 'user' }));
// /admin/* 上 IP 维度严格 rate-limit + audit log,防止 ADMIN_TOKEN 暴力枚举
app.use('/admin/*',                    rateLimit({ name: 'admin',   windowMs: 60_000, max: 30,  by: 'ip' }));
app.use('/v1/friends/*/sessions',     rateLimit({ name: 'fsess',   windowMs: 60_000, max: 60,  by: 'user' }));
app.use('/v1/friends/*/daily-summary',rateLimit({ name: 'fdsum',   windowMs: 60_000, max: 60,  by: 'user' }));

// ---- Health

app.get('/health', (c) => c.json({
  ok: true,
  ts: Date.now(),
  version: API_VERSION,
  startedAt: STARTED_AT,
  uptimeMs: Date.now() - STARTED_AT,
}));

// App Store 必需的公开法律与支持页面。无登录、无追踪、无第三方脚本。
app.get('/privacy', (c) => c.html(PRIVACY_PAGE));
app.get('/terms', (c) => c.html(TERMS_PAGE));
app.get('/support', (c) => c.html(SUPPORT_PAGE));

// ---- Auth: Sign in with Apple

app.post('/v1/auth/apple', async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const { idToken, displayName } = body || {};
  if (!idToken) return c.json({ error: 'idToken required' }, 400);
  try {
    const user = await authenticateApple({ idToken, displayName });
    const sessionToken = await issueSessionToken(user.user_id);
    return c.json({ sessionToken, user: publicUser(user) });
  } catch (e) {
    console.error('[auth/apple] verify failed:', e.message);
    return c.json({ error: 'invalid Apple token' }, 401);
  }
});

// ---- Session middleware

async function requireSession(c, next) {
  const auth = c.req.header('Authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) return c.json({ error: 'missing Bearer token' }, 401);
  try {
    const userId = await verifySessionToken(token);
    const user = getUser(userId);
    if (!user) return c.json({ error: 'user not found' }, 401);
    c.set('userId', userId);
    c.set('user', user);
    await next();
  } catch {
    return c.json({ error: 'invalid session token' }, 401);
  }
}

// ---- Me

app.get('/v1/me', requireSession, (c) => {
  return c.json({ user: publicUser(c.get('user')) });
});

app.patch('/v1/me', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  if (body.displayName && typeof body.displayName === 'string' && body.displayName.length > 64) {
    return c.json({ error: 'displayName 太长(最多 64 字符)' }, 400);
  }
  const user = c.get('user');
  upsertUser({
    userId: user.user_id,
    appleSub: user.apple_sub,
    emailHash: user.email_hash,
    displayName: body.displayName || user.display_name,
  });
  const updated = getUser(user.user_id);
  return c.json({ user: publicUser(updated) });
});

app.delete('/v1/me', requireSession, (c) => {
  deleteUser(c.get('userId'));
  return c.json({ ok: true });
});

app.put('/v1/me/stress', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const scoreRaw = Number(body.score);
  const score = Math.round(scoreRaw);
  const level = typeof body.level === 'string' ? body.level : '';
  const displayName = typeof body.displayName === 'string' ? body.displayName.slice(0, 64) : c.get('user').display_name;
  if (!Number.isFinite(scoreRaw) || score < 0 || score > 100) {
    return c.json({ error: 'score must be 0...100' }, 400);
  }
  if (!['calm', 'relaxed', 'mild', 'high', 'extreme', 'unknown'].includes(level)) {
    return c.json({ error: 'invalid stress level' }, 400);
  }
  const snapshot = upsertStressSnapshot({
    userId: c.get('userId'),
    score,
    level,
    displayName,
  });
  return c.json({ ok: true, snapshot: publicStressSnapshot(snapshot, c.get('user')) });
});

app.delete('/v1/me/stress', requireSession, (c) => {
  deleteStressSnapshot(c.get('userId'));
  return c.json({ ok: true });
});

// ---- Devices

app.post('/v1/devices', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const { deviceId, apnsToken } = body || {};
  if (!deviceId || !apnsToken) return c.json({ error: 'deviceId and apnsToken required' }, 400);
  upsertDevice({ deviceId, userId: c.get('userId'), apnsToken });
  return c.json({ ok: true });
});

app.delete('/v1/devices/:deviceId', requireSession, (c) => {
  const deviceId = c.req.param('deviceId') || '';
  if (!deviceId || deviceId.length > 80) return c.json({ error: 'invalid deviceId' }, 400);
  deleteDevice({ deviceId, userId: c.get('userId') });
  // 幂等:设备已经解绑也返回成功,客户端退出不需要因重复点击卡住。
  return c.json({ ok: true });
});

// ---- Legacy Invites — REMOVED in v0.6.0

// 老 by-email + CKShare URL 邀请流程已完全废弃 — 全部改走 /v1/friend-requests + 6 位 publicId。
// 老 client 仍可能请求这些路径(在升级前的版本),所以保留 410 Gone 软着陆而不是 404
// 让客户端能识别 "endpoint gone, please update"。
const legacyInviteGone = (c) => c.json({
  error: 'gone',
  message: 'invite-by-email/CKShare API removed in v0.6.0 — use /v1/friend-requests + publicId',
}, 410);
app.post('/v1/invites',                requireSession, legacyInviteGone);
app.get('/v1/invites/inbox',           requireSession, legacyInviteGone);
app.post('/v1/invites/by-code',        requireSession, legacyInviteGone);
app.post('/v1/invites/:id/accepted',   requireSession, legacyInviteGone);

// ---- Look up user by public_id

app.get('/v1/users/by-public-id/:id', requireSession, (c) => {
  const id = c.req.param('id') || '';
  const u = findUserByPublicId(id);
  if (!u) return c.json({ error: '未找到该共振 ID' }, 404);
  return c.json({
    user: {
      userId: u.user_id,
      publicId: u.public_id,
      displayName: u.display_name,
    },
  });
});

// ---- Friend requests

app.post('/v1/friend-requests', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const { toPublicId, shareUrl = '', isReverse } = body || {};
  if (!toPublicId) {
    return c.json({ error: 'toPublicId required' }, 400);
  }
  if (typeof toPublicId !== 'string' || toPublicId.length !== 6) {
    return c.json({ error: 'toPublicId must be 6 chars' }, 400);
  }
  if (typeof shareUrl !== 'string' || shareUrl.length > 2048) {
    return c.json({ error: 'shareUrl invalid or too long' }, 400);
  }
  const target = findUserByPublicId(toPublicId);
  if (!target) return c.json({ error: '未找到该共振 ID' }, 404);
  const fromUser = c.get('user');
  if (target.user_id === fromUser.user_id) {
    return c.json({ error: '不能添加自己' }, 400);
  }

  const reverse = !!isReverse;
  const requestId = randomUUID();
  const fr = createFriendRequest({
    requestId,
    fromUserId: fromUser.user_id,
    toUserId: target.user_id,
    shareUrl,
    ttlHours: 7 * 24, // 7 天
    isReverse: reverse,
  });

  // 推送给对方
  const tokens = getDevicesForUser(target.user_id).map(d => d.apns_token);
  // 兼容旧 client 的 isReverse 字段;新 client 已改成 server 双向 friendship,不再需要 CKShare 反向通道.
  const pushTitle = reverse ? '密友关系已建立 ✨' : '收到共振密友请求';
  const pushBody = reverse
    ? `${fromUser.display_name || '好友'} 已与你建立共振关系`
    : `${fromUser.display_name || '某位朋友'} 想加你为共振密友`;
  sendAlert({
    tokens,
    title: pushTitle,
    body: pushBody,
    data: {
      type: 'friend_request_received',
      requestId,
      isReverse: reverse ? 1 : 0,
      fromUserId: fromUser.user_id,
      fromPublicId: fromUser.public_id || '',
      fromName: fromUser.display_name || '好友',
    },
  }).catch(e => console.error('[apns] friend req push failed:', e));
  sendSilent({
    tokens,
    data: {
      type: 'friend_request_received',
      requestId,
      fromUserId: fromUser.user_id,
      fromPublicId: fromUser.public_id || '',
      fromName: fromUser.display_name || '好友',
    },
  }).catch(e => console.error('[apns] friend req silent failed:', e));

  return c.json({
    requestId,
    expiresAt: fr.expires_at,
    isReverse: reverse,
    target: {
      publicId: target.public_id,
      displayName: target.display_name,
    },
  });
});

app.get('/v1/friend-requests/inbox', requireSession, (c) => {
  const list = getInboxRequests(c.get('userId'));
  return c.json({
    requests: list.map(r => ({
      requestId: r.request_id,
      fromUserId: r.from_user_id,
      fromName: r.from_display_name,
      fromPublicId: r.from_public_id,
      shareUrl: r.share_url,
      isReverse: !!r.is_reverse,
      createdAt: r.created_at,
      expiresAt: r.expires_at,
    })),
  });
});

app.get('/v1/friend-requests/outgoing', requireSession, (c) => {
  const list = getOutgoingRequests(c.get('userId'));
  return c.json({
    requests: list.map(r => ({
      requestId: r.request_id,
      toUserId: r.to_user_id,
      toName: r.to_display_name,
      toPublicId: r.to_public_id,
      isReverse: !!r.is_reverse,
      createdAt: r.created_at,
      expiresAt: r.expires_at,
    })),
  });
});

app.post('/v1/friend-requests/:id/accept', requireSession, async (c) => {
  const requestId = c.req.param('id');
  const userId = c.get('userId');
  const fr = getFriendRequest(requestId);
  if (!fr) return c.json({ error: 'not found' }, 404);

  const ok = actOnFriendRequest({ requestId, userId, status: 'accepted' });
  if (!ok) return c.json({ error: '请求已过期或无权操作' }, 410);

  recordFriendship(fr.from_user_id, fr.to_user_id);

  // 推送给发起方:已接受
  // 兼容旧 reverse request:旧 client 可能仍创建反向请求,这里保持不重复打扰.
  if (!fr.is_reverse) {
    const fromDevices = getDevicesForUser(fr.from_user_id);
    const tokens = fromDevices.map(d => d.apns_token);
    const acceptor = getUser(userId);
    sendAlert({
      tokens,
      title: '请求已接受 ✨',
      body: `${acceptor.display_name || '好友'} 接受了你的共振密友请求`,
      data: {
        type: 'friend_request_accepted',
        requestId,
        friendUserId: acceptor.user_id,
        friendPublicId: acceptor.public_id || '',
        friendName: acceptor.display_name || '好友',
      },
    }).catch(e => console.error('[apns] accept push failed:', e));
    sendSilent({
      tokens,
      data: {
        type: 'friend_request_accepted',
        requestId,
        friendUserId: acceptor.user_id,
        friendPublicId: acceptor.public_id || '',
        friendName: acceptor.display_name || '好友',
      },
    }).catch(e => console.error('[apns] accept silent failed:', e));
  } else {
    console.log('[friend-requests] skipping accept-push for reverse request', requestId);
  }

  return c.json({
    ok: true,
    shareUrl: fr.share_url || '',
    fromUserId: fr.from_user_id,
    isReverse: !!fr.is_reverse,
  });
});

app.post('/v1/friend-requests/:id/decline', requireSession, (c) => {
  const requestId = c.req.param('id');
  const userId = c.get('userId');
  const ok = actOnFriendRequest({ requestId, userId, status: 'declined' });
  if (!ok) return c.json({ error: 'not found / already acted' }, 404);
  return c.json({ ok: true });
});

app.post('/v1/friend-requests/:id/cancel', requireSession, (c) => {
  const requestId = c.req.param('id');
  const fromUserId = c.get('userId');
  const ok = cancelOutgoingFriendRequest({ requestId, fromUserId });
  if (!ok) return c.json({ error: 'not found / already acted' }, 404);
  return c.json({ ok: true });
});

// ---- Friends

app.get('/v1/friends', requireSession, (c) => {
  const friends = getFriendsForUser(c.get('userId'));
  return c.json({
    friends: friends.map(f => ({
      userId: f.user_id,
      publicId: f.public_id,
      displayName: f.display_name,
    })),
  });
});

app.get('/v1/friends/stress', requireSession, (c) => {
  const rows = getFriendStressSnapshots(c.get('userId'));
  return c.json({
    friends: rows.map(r => ({
      userId: r.user_id,
      publicId: r.public_id,
      displayName: r.stress_display_name || r.user_display_name || '好友',
      stressScore: r.score == null ? 0 : r.score,
      stressLevel: r.level || 'unknown',
      lastUpdated: r.updated_at || null,
      friendshipCreatedAt: r.friendship_created_at || null,
      hasStress: r.score != null,
    })),
  });
});

app.put('/v1/friends/:userId/mute', requireSession, (c) => {
  const currentUserId = c.get('userId');
  const targetUserId = c.req.param('userId');
  if (!targetUserId || targetUserId === currentUserId) {
    return c.json({ error: 'invalid friend id' }, 400);
  }
  if (!areFriends(currentUserId, targetUserId)) {
    return c.json({ error: 'not friends' }, 403);
  }
  setFriendMute({ userId: currentUserId, mutedUserId: targetUserId, muted: true });
  return c.json({ ok: true });
});

app.delete('/v1/friends/:userId/mute', requireSession, (c) => {
  const currentUserId = c.get('userId');
  const targetUserId = c.req.param('userId');
  if (!targetUserId || targetUserId === currentUserId) {
    return c.json({ error: 'invalid friend id' }, 400);
  }
  if (!areFriends(currentUserId, targetUserId)) {
    return c.json({ ok: true, alreadyRemoved: true });
  }
  setFriendMute({ userId: currentUserId, mutedUserId: targetUserId, muted: false });
  return c.json({ ok: true });
});

app.delete('/v1/friends/:userId', requireSession, (c) => {
  const currentUser = c.get('user');
  const currentUserId = c.get('userId');
  const targetUserId = c.req.param('userId');
  if (!targetUserId || targetUserId === currentUserId) {
    return c.json({ error: 'invalid friend id' }, 400);
  }
  if (!areFriends(currentUserId, targetUserId)) {
    return c.json({ ok: true, alreadyRemoved: true });
  }

  const removedAt = Date.now();
  deleteFriendship(currentUserId, targetUserId);

  const targetDevices = getDevicesForUser(targetUserId);
  const tokens = targetDevices.map(d => d.apns_token);
  sendAlert({
    tokens,
    title: '密友绑定已解除',
    body: `${currentUser.display_name || '好友'} 已解除与你的共振关怀`,
    data: {
      type: 'friend_removed',
      fromUserId: currentUserId,
      fromPublicId: currentUser.public_id || '',
      fromName: currentUser.display_name || '',
      removedAt: String(removedAt),
    },
  }).catch(e => console.error('[apns] friend removed push failed:', e));
  sendSilent({
    tokens,
    data: {
      type: 'friend_removed',
      fromUserId: currentUserId,
      fromPublicId: currentUser.public_id || '',
      fromName: currentUser.display_name || '',
      removedAt: String(removedAt),
    },
  }).catch(e => console.error('[apns] friend removed silent failed:', e));

  return c.json({ ok: true, removedAt });
});

// ---- Care events (heartbeat / encourage / training invites)

const CARE_EVENT_ALIASES = new Map([
  ['heartbeat', 'heartbeat'],
  ['breathingInvite', 'breathing_invite'],
  ['breathing_invite', 'breathing_invite'],
  ['meditationInvite', 'meditation_invite'],
  ['meditation_invite', 'meditation_invite'],
  ['sessionCompleted', 'session_completed'],
  ['session_completed', 'session_completed'],
  ['encourage', 'encourage'],
  ['trendSummary', 'trend_summary'],
  ['trend_summary', 'trend_summary'],
]);

app.post('/v1/care-events', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const { toUserId, type, message, payload, replyToEventId } = body || {};
  const normalizedType = CARE_EVENT_ALIASES.get(type);
  const fromUser = c.get('user');
  const fromUserId = c.get('userId');
  if (!toUserId || typeof toUserId !== 'string') {
    return c.json({ error: 'toUserId required' }, 400);
  }
  if (!type || typeof type !== 'string' || !normalizedType) {
    return c.json({ error: 'invalid care event type' }, 400);
  }
  if (toUserId === fromUserId) {
    return c.json({ error: 'cannot send to yourself' }, 400);
  }
  if (!areFriends(fromUserId, toUserId)) {
    return c.json({ error: 'not friends' }, 403);
  }
  if (message && (typeof message !== 'string' || message.length > 240)) {
    return c.json({ error: 'message too long' }, 400);
  }

  let originalEvent = null;
  if (replyToEventId != null) {
    if (typeof replyToEventId !== 'string' || replyToEventId.length > 80) {
      return c.json({ error: 'invalid replyToEventId' }, 400);
    }
    originalEvent = getCareEvent(replyToEventId);
    if (!originalEvent) return c.json({ error: 'original care event not found' }, 404);
    if (originalEvent.to_user_id !== fromUserId || originalEvent.from_user_id !== toUserId) {
      return c.json({ error: 'reply target does not match this conversation' }, 403);
    }
  }

  let payloadJSON = null;
  if (payload && typeof payload === 'object') {
    payloadJSON = JSON.stringify(payload).slice(0, 1000);
  }
  const eventId = randomUUID();
  const event = createCareEvent({
    eventId,
    fromUserId,
    toUserId,
    type: normalizedType,
    message,
    payloadJSON,
    replyToEventId: originalEvent?.event_id || null,
  });

  const data = {
    type: 'care_event',
    eventId,
    eventType: normalizedType,
    fromUserId,
    fromPublicId: fromUser.public_id || '',
    fromName: fromUser.display_name || '好友',
    message: message || '',
    payloadJSON: payloadJSON || '',
    replyToEventId: originalEvent?.event_id || '',
  };

  const mutedByRecipient = isFriendMuted(toUserId, fromUserId);
  if (!mutedByRecipient) {
    const tokens = getDevicesForUser(toUserId).map(d => d.apns_token);
    sendAlert({
      tokens,
      title: careEventTitle(normalizedType, fromUser.display_name || '好友'),
      body: careEventBody(normalizedType, message, payload || {}),
      data,
      category: careEventCategory(normalizedType),
    }).catch(e => console.error('[apns] care event push failed:', e));
    sendSilent({ tokens, data }).catch(e => console.error('[apns] care event silent failed:', e));
  }

  return c.json({
    ok: true,
    mutedByRecipient,
    event: publicCareEvent(event, fromUser, getUser(toUserId)),
  });
});

app.get('/v1/care-events/inbox', requireSession, (c) => {
  const limitRaw = Number(c.req.query('limit') || 80);
  const limit = Math.max(1, Math.min(120, Number.isFinite(limitRaw) ? limitRaw : 80));
  const events = getInboxCareEvents(c.get('userId'), limit);
  return c.json({ events: events.map(publicCareEventRow) });
});

app.get('/v1/care-events/timeline', requireSession, (c) => {
  const userId = c.get('userId');
  const friendUserId = c.req.query('friendUserId') || null;
  const limitRaw = Number(c.req.query('limit') || 80);
  const limit = Math.max(1, Math.min(120, Number.isFinite(limitRaw) ? limitRaw : 80));
  if (friendUserId) {
    if (friendUserId === userId) return c.json({ error: 'invalid friendUserId' }, 400);
    if (!areFriends(userId, friendUserId)) return c.json({ error: 'not friends' }, 403);
  }
  const events = getCareEventTimeline(userId, friendUserId, limit);
  return c.json({ events: events.map(publicCareTimelineRow) });
});

app.post('/v1/care-events/read', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  if (body.eventIds != null && !Array.isArray(body.eventIds)) {
    return c.json({ error: 'eventIds must be an array' }, 400);
  }
  if (Array.isArray(body.eventIds)
      && (body.eventIds.length > 120
          || body.eventIds.some(id => typeof id !== 'string' || id.length === 0 || id.length > 80))) {
    return c.json({ error: 'invalid eventIds' }, 400);
  }
  const result = markCareEventsRead(c.get('userId'), body.eventIds ?? null);
  return c.json({ ok: true, updated: result.changes, readAt: result.readAt });
});

app.delete('/v1/care-events/:id', requireSession, (c) => {
  const ok = deleteCareEvent({ eventId: c.req.param('id'), userId: c.get('userId') });
  if (!ok) return c.json({ error: 'not found' }, 404);
  return c.json({ ok: true });
});

// ---- Stress bottles (controlled UGC)

const BOTTLE_MOOD_TAGS = new Set(['疲惫', '焦虑', '委屈', '失眠', '想被抱抱', '撑不住']);
const BOTTLE_REPORT_REASONS = new Set(['spam', 'abuse', 'sexual', 'self_harm', 'other']);

app.post('/v1/bottles', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const fromUserId = c.get('userId');
  const message = normalizeText(body.message, 500);
  const moodTag = typeof body.moodTag === 'string' ? body.moodTag.slice(0, 16) : '';
  const stressScoreRaw = body.stressScore == null ? null : Number(body.stressScore);
  const stressScore = Number.isFinite(stressScoreRaw) ? Math.round(stressScoreRaw) : null;
  const stressLevel = typeof body.stressLevel === 'string' ? body.stressLevel : null;

  if (!BOTTLE_MOOD_TAGS.has(moodTag)) {
    return c.json({ error: 'invalid mood tag' }, 400);
  }
  if (message.length < 4) {
    return c.json({ error: '至少写 4 个字' }, 400);
  }
  if (stressScore != null && (stressScore < 0 || stressScore > 100)) {
    return c.json({ error: 'stressScore must be 0...100' }, 400);
  }
  if (stressLevel && !['calm', 'relaxed', 'mild', 'high', 'extreme', 'unknown'].includes(stressLevel)) {
    return c.json({ error: 'invalid stress level' }, 400);
  }
  const safety = contentSafety(message);
  if (!safety.ok) {
    return c.json({ error: safety.message, code: safety.code }, 400);
  }
  const todayCount = countUserBottlesSince(fromUserId, Date.now() - 24 * 3600_000);
  if (todayCount >= 3) {
    return c.json({ error: '今天已经投过 3 个瓶子了,明天再来' }, 429);
  }

  const bottle = createStressBottle({
    bottleId: randomUUID(),
    authorUserId: fromUserId,
    moodTag,
    stressScore,
    stressLevel,
    message,
    anonymous: body.anonymous !== false,
    ttlHours: 72,
  });
  return c.json({ ok: true, bottle: publicBottleRow(bottle, fromUserId) });
});

app.get('/v1/bottles/sea', requireSession, (c) => {
  const limitRaw = Number(c.req.query('limit') || 8);
  const limit = Math.max(1, Math.min(20, Number.isFinite(limitRaw) ? limitRaw : 8));
  const bottles = getSeaStressBottles({ viewerUserId: c.get('userId'), limit });
  return c.json({ bottles: bottles.map(row => publicBottleRow(row, c.get('userId'))) });
});

app.get('/v1/bottles/mine', requireSession, (c) => {
  const limitRaw = Number(c.req.query('limit') || 20);
  const limit = Math.max(1, Math.min(50, Number.isFinite(limitRaw) ? limitRaw : 20));
  const bottles = getMyStressBottles({ userId: c.get('userId'), limit });
  return c.json({ bottles: bottles.map(row => publicBottleRow(row, c.get('userId'))) });
});

app.post('/v1/bottles/:id/reply', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const message = normalizeText(body.message, 240);
  if (message.length < 4) {
    return c.json({ error: '至少写 4 个字' }, 400);
  }
  const safety = contentSafety(message);
  if (!safety.ok) {
    return c.json({ error: safety.message, code: safety.code }, 400);
  }
  const before = getStressBottleForUser({
    bottleId: c.req.param('id'),
    viewerUserId: c.get('userId'),
    includeOwn: false,
  });
  if (!before) return c.json({ error: '瓶子不存在或已被接住' }, 404);

  const reply = replyToStressBottle({
    replyId: randomUUID(),
    bottleId: c.req.param('id'),
    fromUserId: c.get('userId'),
    message,
  });
  if (!reply) return c.json({ error: '瓶子不存在或已被接住' }, 404);

  const fromUser = c.get('user');
  const tokens = getDevicesForUser(before.author_user_id).map(d => d.apns_token);
  sendAlert({
    tokens,
    title: '有人接住了你的瓶子',
    body: message,
    data: {
      type: 'bottle_reply',
      bottleId: before.bottle_id,
      replyId: reply.reply_id,
      fromName: fromUser.display_name || 'Tempo 用户',
    },
  }).catch(e => console.error('[apns] bottle reply push failed:', e));

  return c.json({ ok: true, reply: publicBottleReply(reply, fromUser) });
});

app.post('/v1/bottles/:id/report', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const reason = BOTTLE_REPORT_REASONS.has(body.reason) ? body.reason : 'other';
  const bottle = getStressBottleForUser({
    bottleId: c.req.param('id'),
    viewerUserId: c.get('userId'),
    includeOwn: false,
  });
  if (!bottle) return c.json({ ok: true });
  createModerationReport({
    reportId: randomUUID(),
    reporterUserId: c.get('userId'),
    targetType: 'bottle',
    targetId: c.req.param('id'),
    reason,
  });
  return c.json({ ok: true });
});

app.post('/v1/bottles/:id/reply/report', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const reason = BOTTLE_REPORT_REASONS.has(body.reason) ? body.reason : 'other';
  const reply = hideBottleReplyForOwner({
    bottleId: c.req.param('id'),
    ownerUserId: c.get('userId'),
  });
  if (!reply) return c.json({ ok: true });
  createModerationReport({
    reportId: randomUUID(),
    reporterUserId: c.get('userId'),
    targetType: 'reply',
    targetId: reply.reply_id,
    reason,
  });
  return c.json({ ok: true });
});

app.post('/v1/bottles/:id/reply/block-author', requireSession, (c) => {
  const reply = getBottleReplyForOwner({
    bottleId: c.req.param('id'),
    ownerUserId: c.get('userId'),
  });
  if (reply?.from_user_id) {
    blockUser({ userId: c.get('userId'), blockedUserId: reply.from_user_id });
    hideBottleReplyForOwner({ bottleId: c.req.param('id'), ownerUserId: c.get('userId') });
  }
  return c.json({ ok: true });
});

app.post('/v1/bottles/:id/block-author', requireSession, (c) => {
  const bottle = getStressBottleForUser({
    bottleId: c.req.param('id'),
    viewerUserId: c.get('userId'),
    includeOwn: false,
  });
  if (bottle?.author_user_id) {
    blockUser({ userId: c.get('userId'), blockedUserId: bottle.author_user_id });
  }
  return c.json({ ok: true });
});

app.delete('/v1/bottles/:id', requireSession, (c) => {
  const ok = deleteStressBottle({ bottleId: c.req.param('id'), userId: c.get('userId') });
  if (!ok) return c.json({ error: 'not found' }, 404);
  return c.json({ ok: true });
});

// ============================================================
// ---- Phase 2: 全量数据上传 + 朋友共享
// ============================================================

// --- stress_history(自己写 / 自己查 / 朋友查)

app.post('/v1/me/stress/history', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const score = Number(body.score);
  const level = String(body.level || '');
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    return c.json({ error: 'score must be 0..100' }, 400);
  }
  if (!level) return c.json({ error: 'level required' }, 400);
  const algorithmVersion = Number(body.algorithmVersion) || 1;
  appendStressHistory({
    userId: c.get('userId'),
    score: Math.round(score),
    level,
    recordedAt: Number(body.recordedAt) || Date.now(),
    algorithmVersion: Math.max(1, Math.min(99, Math.trunc(algorithmVersion))),
  });
  return c.json({ ok: true });
});

app.get('/v1/me/stress/history', requireSession, (c) => {
  const days = Math.max(1, Math.min(365, Number(c.req.query('days') || 30)));
  const sinceTs = Date.now() - days * 86400_000;
  const rows = getStressHistory({
    userId: c.get('userId'),
    sinceTs,
    untilTs: Date.now(),
  });
  return c.json({ history: rows.map(r => ({
    historyId: r.history_id, score: r.score, level: r.level, recordedAt: r.recorded_at,
    algorithmVersion: r.algorithm_version || 1,
  })) });
});

app.get('/v1/friends/:userId/stress/history', requireSession, (c) => {
  const me = c.get('userId');
  const target = c.req.param('userId');
  if (!areFriends(me, target)) return c.json({ error: 'not friends' }, 403);
  const prefs = getSharePrefs(target);
  if (!prefs.shareStress) return c.json({ history: [], shared: false });
  const days = Math.max(1, Math.min(90, Number(c.req.query('days') || 7)));
  const sinceTs = Date.now() - days * 86400_000;
  const rows = getStressHistory({ userId: target, sinceTs, untilTs: Date.now(), limit: 2016 });   // 7d * 24h * 12(每 5min 一条)≤ 2016
  return c.json({
    shared: true,
    history: rows.map(r => ({ historyId: r.history_id, score: r.score, level: r.level, recordedAt: r.recorded_at })),
  });
});

// --- hrv_samples(批量上传 / 查 / 朋友查)

app.post('/v1/me/hrv', requireSession, async (c) => {
  const userId = c.get('userId');
  if (!getSharePrefs(userId).shareHRV) {
    return c.json({ error: 'hrv sharing disabled' }, 403);
  }
  const body = await c.req.json().catch(() => ({}));
  const samples = Array.isArray(body.samples) ? body.samples : [];
  if (samples.length === 0) return c.json({ ok: true, accepted: 0 });
  if (samples.length > 500) return c.json({ error: 'too many samples (max 500)' }, 400);
  const cleaned = samples
    .map(s => ({
      valueMs: Number(s.valueMs),
      measuredAt: Number(s.measuredAt),
      source: typeof s.source === 'string' ? s.source.slice(0, 32) : null,
    }))
    .filter(s => Number.isFinite(s.valueMs) && Number.isFinite(s.measuredAt) && s.valueMs > 0 && s.valueMs < 1000);
  const n = appendHRVSamples({ userId, samples: cleaned });
  return c.json({ ok: true, accepted: n });
});

app.get('/v1/me/hrv', requireSession, (c) => {
  const days = Math.max(1, Math.min(90, Number(c.req.query('days') || 7)));
  const sinceTs = Date.now() - days * 86400_000;
  const rows = getHRVHistory({ userId: c.get('userId'), sinceTs, untilTs: Date.now() });
  return c.json({ samples: rows.map(r => ({
    sampleId: r.sample_id, valueMs: r.value_ms, source: r.source, measuredAt: r.measured_at
  })) });
});

app.delete('/v1/me/hrv', requireSession, (c) => {
  return c.json({ ok: true, deleted: deleteHRVSamples(c.get('userId')) });
});

// --- breathing / meditation sessions(上传 / 查 / 朋友查)

app.post('/v1/me/sessions', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const kind = body.type;
  const minutes = Math.max(1, Math.min(180, Number(body.minutes) || 0));
  const completedAt = Number(body.completedAt) || Date.now();
  const sessionId = String(body.sessionId || randomUUID()).slice(0, 64);
  if (kind === 'breathing') {
    const pattern = String(body.pattern || '').slice(0, 32);
    if (!pattern) return c.json({ error: 'pattern required' }, 400);
    createBreathingSession({ sessionId, userId: c.get('userId'), pattern, minutes, completedAt });
  } else if (kind === 'meditation') {
    createMeditationSession({ sessionId, userId: c.get('userId'), minutes, completedAt });
  } else {
    return c.json({ error: 'type must be breathing|meditation' }, 400);
  }
  return c.json({ ok: true, sessionId });
});

app.get('/v1/me/sessions', requireSession, (c) => {
  const days = Math.max(1, Math.min(90, Number(c.req.query('days') || 7)));
  const sinceTs = Date.now() - days * 86400_000;
  const breath = getBreathingSessions({ userId: c.get('userId'), sinceTs, untilTs: Date.now() });
  const med = getMeditationSessions({ userId: c.get('userId'), sinceTs, untilTs: Date.now() });
  return c.json({
    breathing: breath.map(s => ({ sessionId: s.session_id, pattern: s.pattern, minutes: s.minutes, completedAt: s.completed_at })),
    meditation: med.map(s => ({ sessionId: s.session_id, minutes: s.minutes, completedAt: s.completed_at })),
  });
});

app.get('/v1/friends/:userId/sessions', requireSession, (c) => {
  const me = c.get('userId');
  const target = c.req.param('userId');
  if (!areFriends(me, target)) return c.json({ error: 'not friends' }, 403);
  const prefs = getSharePrefs(target);
  if (!prefs.shareTraining) return c.json({ shared: false, breathing: [], meditation: [] });
  const days = Math.max(1, Math.min(30, Number(c.req.query('days') || 7)));
  const sinceTs = Date.now() - days * 86400_000;
  const breath = getBreathingSessions({ userId: target, sinceTs, untilTs: Date.now() });
  const med = getMeditationSessions({ userId: target, sinceTs, untilTs: Date.now() });
  return c.json({
    shared: true,
    breathing: breath.map(s => ({ sessionId: s.session_id, pattern: s.pattern, minutes: s.minutes, completedAt: s.completed_at })),
    meditation: med.map(s => ({ sessionId: s.session_id, minutes: s.minutes, completedAt: s.completed_at })),
  });
});

// --- daily_summary(client 兜底 upsert / 自己查 / 朋友查)

app.post('/v1/me/daily-summary', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const date = String(body.date || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return c.json({ error: 'date must be YYYY-MM-DD' }, 400);
  }
  upsertDailySummary({
    userId: c.get('userId'),
    date,
    payload: body,   // 字段名 stressAvg / hrvAvg / breathingCount 等
  });
  return c.json({ ok: true });
});

app.get('/v1/me/daily-summary', requireSession, (c) => {
  const dateFrom = String(c.req.query('from') || '');
  const dateTo = String(c.req.query('to') || dateFrom);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateFrom)) return c.json({ error: 'from required (YYYY-MM-DD)' }, 400);
  const rows = getDailySummary({ userId: c.get('userId'), dateFrom, dateTo });
  return c.json({ summaries: rows.map(r => mapDailySummary(r)) });
});

app.get('/v1/friends/:userId/daily-summary', requireSession, (c) => {
  const me = c.get('userId');
  const target = c.req.param('userId');
  if (!areFriends(me, target)) return c.json({ error: 'not friends' }, 403);
  const prefs = getSharePrefs(target);
  const dateFrom = String(c.req.query('from') || '');
  const dateTo = String(c.req.query('to') || dateFrom);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateFrom)) return c.json({ error: 'from required (YYYY-MM-DD)' }, 400);
  const rows = getDailySummary({ userId: target, dateFrom, dateTo });
  // 朋友看的版本:根据 prefs 屏蔽某些字段
  const filtered = rows.map(r => {
    const m = mapDailySummary(r);
    if (!prefs.shareStress) {
      m.stressAvg = null; m.stressMax = null; m.stressMin = null; m.stressHighMinutes = null;
    }
    if (!prefs.shareHRV) m.hrvAvg = null;
    if (!prefs.shareTraining) {
      m.breathingCount = null; m.breathingMinutes = null;
      m.meditationCount = null; m.meditationMinutes = null;
    }
    return m;
  });
  return c.json({ summaries: filtered, prefs });
});

// --- 用户偏好(分享我的训练 toggle 等)

app.get('/v1/me/share-prefs', requireSession, (c) => {
  return c.json({ prefs: getSharePrefs(c.get('userId')) });
});

app.put('/v1/me/share-prefs', requireSession, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const updated = updateSharePrefs({
    userId: c.get('userId'),
    shareStress: typeof body.shareStress === 'boolean' ? body.shareStress : null,
    shareTraining: typeof body.shareTraining === 'boolean' ? body.shareTraining : null,
    shareHRV: typeof body.shareHRV === 'boolean' ? body.shareHRV : null,
  });
  if (body.shareHRV === false) {
    deleteHRVSamples(c.get('userId'));
  }
  return c.json({ prefs: updated });
});

// ---- Minimal moderation admin API

async function requireAdmin(c, next) {
  const expected = process.env.ADMIN_TOKEN;
  if (!expected) return c.json({ error: 'admin disabled' }, 404);

  // 可选 IP 白名单:ADMIN_IP_WHITELIST=1.2.3.4,5.6.7.8(若不配则全网允许 + token 校验 + rate-limit)
  const allowedIPs = (process.env.ADMIN_IP_WHITELIST || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);
  if (allowedIPs.length > 0) {
    const xff = (c.req.header('x-forwarded-for') || '').split(',')[0].trim();
    if (!xff || !allowedIPs.includes(xff)) {
      console.warn(`[admin] reject IP ${xff || '(none)'} for ${c.req.path}`);
      return c.json({ error: 'forbidden' }, 403);
    }
  }

  const token = c.req.header('X-Tempo-Admin-Token') || '';
  if (token !== expected) {
    const xff = (c.req.header('x-forwarded-for') || '').split(',')[0].trim();
    console.warn(`[admin] bad token from ${xff || '(unknown)'} for ${c.req.path}`);
    return c.json({ error: 'forbidden' }, 403);
  }

  // Audit log:成功的 admin 操作都打日志(N5 推荐)
  const xff = (c.req.header('x-forwarded-for') || '').split(',')[0].trim();
  console.log(`[admin-audit] ${c.req.method} ${c.req.path} from ${xff || '(unknown)'}`);
  await next();
}

app.get('/admin/moderation/reports', requireAdmin, (c) => {
  const limitRaw = Number(c.req.query('limit') || 100);
  const limit = Math.max(1, Math.min(300, Number.isFinite(limitRaw) ? limitRaw : 100));
  const status = ['open', 'resolved', 'all'].includes(c.req.query('status'))
    ? c.req.query('status')
    : 'open';
  return c.json({
    reports: listModerationReports({ limit, status }).map(publicModerationReport),
  });
});

app.post('/admin/moderation/reports/:id/resolve', requireAdmin, async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const action = typeof body.action === 'string' ? body.action : '';
  if (!['hide', 'restore', 'dismiss'].includes(action)) {
    return c.json({ error: 'action must be hide, restore, or dismiss' }, 400);
  }
  const report = resolveModerationReport({
    reportId: c.req.param('id'),
    action,
    reviewerNote: normalizeText(body.note, 240),
  });
  if (!report) return c.json({ error: 'not found' }, 404);
  return c.json({ ok: true, report: publicModerationReport(report) });
});

app.post('/admin/bottles/:id/hide', requireAdmin, (c) => {
  const ok = setStressBottleStatus({ bottleId: c.req.param('id'), status: 'hidden' });
  if (!ok) return c.json({ error: 'not found' }, 404);
  return c.json({ ok: true });
});

app.post('/admin/bottles/:id/restore', requireAdmin, (c) => {
  const ok = setStressBottleStatus({ bottleId: c.req.param('id'), status: 'open' });
  if (!ok) return c.json({ error: 'not found' }, 404);
  return c.json({ ok: true });
});

// ---- Helpers

function mapDailySummary(row) {
  return {
    date: row.date,
    stressAvg: row.stress_avg,
    stressMax: row.stress_max,
    stressMin: row.stress_min,
    stressHighMinutes: row.stress_high_minutes,
    hrvAvg: row.hrv_avg,
    breathingCount: row.breathing_count,
    breathingMinutes: row.breathing_minutes,
    meditationCount: row.meditation_count,
    meditationMinutes: row.meditation_minutes,
    updatedAt: row.updated_at,
  };
}

function publicUser(u) {
  return {
    userId: u.user_id,
    displayName: u.display_name,
    publicId: u.public_id,
    hasEmail: !!u.email_hash,
  };
}

function publicCareEvent(event, fromUser, toUser = null) {
  return {
    eventId: event.event_id,
    type: event.type,
    message: event.message || null,
    payload: parsePayload(event.payload_json),
    fromUserId: event.from_user_id,
    fromPublicId: fromUser.public_id || null,
    fromName: fromUser.display_name || '好友',
    toUserId: event.to_user_id,
    toPublicId: toUser?.public_id || null,
    toName: toUser?.display_name || '好友',
    replyToEventId: event.reply_to_event_id || null,
    createdAt: event.created_at,
    readAt: event.read_at || null,
  };
}

function publicCareEventRow(row) {
  return {
    eventId: row.event_id,
    type: row.type,
    message: row.message || null,
    payload: parsePayload(row.payload_json),
    fromUserId: row.from_user_id,
    fromPublicId: row.from_public_id || null,
    fromName: row.from_display_name || '好友',
    toUserId: row.to_user_id,
    toPublicId: null,
    toName: '你',
    replyToEventId: row.reply_to_event_id || null,
    createdAt: row.created_at,
    readAt: row.read_at || null,
  };
}

function publicCareTimelineRow(row) {
  return {
    eventId: row.event_id,
    type: row.type,
    message: row.message || null,
    payload: parsePayload(row.payload_json),
    fromUserId: row.from_user_id,
    fromPublicId: row.from_public_id || null,
    fromName: row.from_display_name || '好友',
    toUserId: row.to_user_id,
    toPublicId: row.to_public_id || null,
    toName: row.to_display_name || '好友',
    replyToEventId: row.reply_to_event_id || null,
    createdAt: row.created_at,
    readAt: row.read_at || null,
  };
}

function publicStressSnapshot(snapshot, user) {
  return {
    userId: snapshot.user_id,
    publicId: user.public_id || null,
    displayName: snapshot.display_name || user.display_name || '好友',
    stressScore: snapshot.score,
    stressLevel: snapshot.level,
    lastUpdated: snapshot.updated_at,
    hasStress: true,
  };
}

function publicBottleRow(row, viewerUserId) {
  const mine = row.author_user_id === viewerUserId;
  const anonymous = !!row.anonymous && !mine;
  return {
    bottleId: row.bottle_id,
    authorUserId: mine ? row.author_user_id : (anonymous ? null : row.author_user_id),
    authorName: mine ? '我' : (anonymous ? '海面上的人' : (row.author_display_name || 'Tempo 用户')),
    moodTag: row.mood_tag,
    stressScore: row.stress_score == null ? null : row.stress_score,
    stressLevel: row.stress_level || null,
    message: row.message,
    anonymous: !!row.anonymous,
    status: row.status,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    reply: row.reply_id ? {
      replyId: row.reply_id,
      fromUserId: row.reply_from_user_id === viewerUserId ? row.reply_from_user_id : null,
      fromName: row.reply_from_user_id === viewerUserId ? '我' : (row.reply_from_display_name || 'Tempo 用户'),
      message: row.reply_message,
      createdAt: row.reply_created_at,
    } : null,
  };
}

function publicBottleReply(reply, fromUser) {
  return {
    replyId: reply.reply_id,
    fromUserId: reply.from_user_id,
    fromName: fromUser.display_name || 'Tempo 用户',
    message: reply.message,
    createdAt: reply.created_at,
  };
}

function publicModerationReport(row) {
  return {
    reportId: row.report_id,
    reporterUserId: row.reporter_user_id,
    reporterName: row.reporter_display_name || 'Tempo 用户',
    targetType: row.target_type,
    targetId: row.target_id,
    reason: row.reason,
    status: row.status || 'open',
    resolution: row.resolution || null,
    reviewerNote: row.reviewer_note || null,
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at,
    bottle: row.target_type === 'bottle' ? {
      message: row.bottle_message || '',
      moodTag: row.bottle_mood_tag || '',
      status: row.bottle_status || '',
      reportCount: row.bottle_report_count || 0,
      authorName: row.bottle_author_display_name || 'Tempo 用户',
    } : null,
    reply: row.target_type === 'reply' ? {
      message: row.reply_message || '',
      status: row.reply_status || '',
      authorName: row.reply_author_display_name || 'Tempo 用户',
    } : null,
  };
}

function parsePayload(payloadJSON) {
  if (!payloadJSON) return {};
  try {
    const parsed = JSON.parse(payloadJSON);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function careEventTitle(type, fromName) {
  switch (type) {
    case 'heartbeat': return `${fromName} 给你发了一次心跳 ❤️`;
    case 'breathing_invite': return `${fromName} 邀你一起呼吸`;
    case 'meditation_invite': return `${fromName} 邀你一起冥想`;
    case 'session_completed': return `${fromName} 完成了一次训练`;
    case 'encourage': return `${fromName} 给你发了鼓励`;
    case 'trend_summary': return `${fromName} 分享了一份压力摘要`;
    default: return `${fromName} 发来一条关怀`;
  }
}

function careEventBody(type, message, payload) {
  switch (type) {
    case 'heartbeat': return '我想你啦,轻轻回一个心跳吧。';
    case 'breathing_invite': return `一起做 ${payload?.minutes || 5} 分钟呼吸`;
    case 'meditation_invite': return `一起做 ${payload?.minutes || 10} 分钟冥想`;
    case 'session_completed': return 'Ta 刚刚完成了练习';
    case 'encourage': return message || '点开看看这句话';
    case 'trend_summary': return `${payload?.range || '近期'}平均 ${payload?.average || '—'}/100,点开查看摘要卡`;
    default: return '点开查看';
  }
}

function careEventCategory(type) {
  if (type === 'breathing_invite' || type === 'meditation_invite') return 'TEMPO_TRAINING_INVITE';
  if (type === 'heartbeat') return 'TEMPO_HEARTBEAT';
  if (type === 'session_completed') return 'TEMPO_SESSION_COMPLETED';
  return undefined;
}

function normalizeText(value, limit) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit);
}

// 归一化:去掉空格 / 标点 / emoji,降低关键词绕过(微 信 / 微_信 / 微.信 等都会被识别)
function normalizeForSafety(text) {
  return text
    .toLowerCase()
    .replace(/[\s 　_\-\.\,\,\,\,\,\:\;\!\?\@\#\$\%\^\&\*\(\)\[\]\{\}\<\>\/\\\|\+\=\~\`\"\']/g, '')
    .normalize('NFKC');
}

function contentSafety(text) {
  const raw = text.toLowerCase();
  const flat = normalizeForSafety(text);

  // 自伤词单独处理 —— 返结构化 error,让 client 弹专属求助 sheet
  const selfHarmTerms = ['自杀', '轻生', '不想活', '想死', '割腕', '自残', '了断', '结束生命'];
  if (selfHarmTerms.some(term => raw.includes(term) || flat.includes(term))) {
    return {
      ok: false,
      code: 'self_harm',
      message: '如果你有伤害自己的冲动,请立刻联系身边可信的人或当地紧急救助。Tempo 漂流瓶不适合处理紧急危机。',
    };
  }

  const blocked = [
    '加微信', '加我微信', '微信号', 'vx', 'qq号', '联系方式',
    '裸聊', '约炮', '援交', '卖淫', '一夜情', '小姐',
    '杀人', '炸弹', '毒品', '冰毒', '大麻',
    '去死', '滚开', '废物', '人渣',
    '邀请码', '推广码', '推荐码', '推广链接',     // 防 ad
  ];
  // 用 flat 命中 / 也用 raw 命中(避免误伤合法语义,例如把"杀人狂"误判)
  if (blocked.some(term => raw.includes(term) || flat.includes(term))) {
    return {
      ok: false,
      code: 'blocked_term',
      message: '内容包含不适合公开漂流瓶的信息(联系方式 / 涉黄涉暴 / 违禁词)',
    };
  }

  // 漂流瓶不承担私聊导流:拦截链接、邮箱和疑似手机号,避免骚扰与线下风险。
  const contactPattern = /(https?:\/\/|www\.|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|(?<!\d)1[3-9]\d{9}(?!\d))/i;
  if (contactPattern.test(text)) {
    return {
      ok: false,
      code: 'contact_info',
      message: '漂流瓶里不要留下链接、邮箱或手机号',
    };
  }

  // 防大段重复字符(如"啊啊啊啊啊啊啊啊啊啊啊啊"刷屏)
  const repeatMatch = flat.match(/(.)\1{15,}/);
  if (repeatMatch) {
    return {
      ok: false,
      code: 'repeated_chars',
      message: '不要重复同一个字符太多次哦',
    };
  }

  return { ok: true };
}

function generateInviteCode() {
  // 6 位字母数字,排除易混(0/O/1/I/L)
  const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return code;
}

// ---- Periodic chores

// 启动 30s 后跑一次清理,之后每 6 小时重复
setTimeout(() => {
  try {
    const r = pruneExpiredRequests();
    console.log('[chores] startup prune:', r);
  } catch (e) {
    console.error('[chores] startup prune failed:', e.message);
  }
}, 30_000).unref();

setInterval(() => {
  try {
    const r = pruneExpiredRequests();
    if ((r.friendRequests + r.invites + (r.bottlesSoft || 0) + (r.bottlesHard || 0) + (r.careEvents || 0) + (r.reports || 0)) > 0) {
      console.log('[chores] prune:', r);
    }
  } catch (e) {
    console.error('[chores] prune failed:', e.message);
  }
}, 6 * 3600_000).unref();

// daily_summary 聚合:每天本地时间 00:30 触发(国内 UTC+8 → server UTC 16:30 跑).
// 实现:每小时检查一次,如果当前小时是 UTC 16(对应国内 00:30),且今天没跑过,就跑.
// 简单可靠,不需要外部 scheduler.
let lastDailyAggregateDate = null;
setInterval(() => {
  const now = new Date();
  const utcHour = now.getUTCHours();
  const todayKey = now.toISOString().slice(0, 10);
  if (utcHour === 16 && lastDailyAggregateDate !== todayKey) {
    try {
      const r = aggregateYesterdayDailySummary();
      console.log('[chores] daily_summary aggregated:', r);
      lastDailyAggregateDate = todayKey;
    } catch (e) {
      console.error('[chores] daily_summary aggregate failed:', e.message);
    }
  }
}, 60 * 60_000).unref();   // 每 1 小时检查一次

// ---- Boot

console.log(`[tempo-api] starting on ${HOST}:${PORT} (version ${API_VERSION})`);
serve({ fetch: app.fetch, port: PORT, hostname: HOST }, (info) => {
  console.log(`[tempo-api] listening on http://${info.address}:${info.port}`);
});
