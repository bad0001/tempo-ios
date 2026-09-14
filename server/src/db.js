import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

// 故意不给 fallback:如果 systemd unit 漏配 DB_PATH,服务直接挂掉,不要默默切到 cwd 的空库
// (那样会导致线上所有 friendship / invite 看起来"消失"——实际数据还在 /var/lib/tempo/,只是没读到)
if (!process.env.DB_PATH) {
  console.error('[tempo-db] FATAL: DB_PATH env var required (expected something like /var/lib/tempo/tempo.db)');
  process.exit(1);
}
const DB_PATH = process.env.DB_PATH;
mkdirSync(dirname(DB_PATH), { recursive: true });

export const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// --- 步骤 1:CREATE TABLE(必须成功;失败就退出,因为 schema 缺失服务跑不动)

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  user_id      TEXT PRIMARY KEY,
  apple_sub    TEXT UNIQUE NOT NULL,
  email_hash   TEXT UNIQUE,
  display_name TEXT,
  public_id    TEXT UNIQUE,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  device_id   TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  apns_token  TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS friend_requests (
  request_id    TEXT PRIMARY KEY,
  from_user_id  TEXT NOT NULL,
  to_user_id    TEXT NOT NULL,
  share_url     TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending',
  is_reverse    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  acted_at      INTEGER,
  FOREIGN KEY (from_user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (to_user_id)   REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS invites (
  invite_id     TEXT PRIMARY KEY,
  invite_code   TEXT UNIQUE NOT NULL,
  from_user_id  TEXT NOT NULL,
  to_email_hash TEXT,
  share_url     TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending',
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  accepted_at   INTEGER,
  accepted_by   TEXT,
  FOREIGN KEY (from_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS friendships (
  user_id_a   TEXT NOT NULL,
  user_id_b   TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id_a, user_id_b),
  FOREIGN KEY (user_id_a) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (user_id_b) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS friend_mutes (
  user_id       TEXT NOT NULL,
  muted_user_id TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (user_id, muted_user_id),
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (muted_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS care_events (
  event_id      TEXT PRIMARY KEY,
  from_user_id  TEXT NOT NULL,
  to_user_id    TEXT NOT NULL,
  type          TEXT NOT NULL,
  message       TEXT,
  payload_json  TEXT,
  reply_to_event_id TEXT,
  created_at    INTEGER NOT NULL,
  read_at       INTEGER,
  FOREIGN KEY (from_user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (to_user_id)   REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (reply_to_event_id) REFERENCES care_events(event_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS stress_snapshots (
  user_id      TEXT PRIMARY KEY,
  score        INTEGER NOT NULL,
  level        TEXT NOT NULL,
  display_name TEXT,
  updated_at   INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS stress_bottles (
  bottle_id      TEXT PRIMARY KEY,
  author_user_id TEXT NOT NULL,
  mood_tag       TEXT NOT NULL,
  stress_score   INTEGER,
  stress_level   TEXT,
  message        TEXT NOT NULL,
  anonymous      INTEGER NOT NULL DEFAULT 1,
  status         TEXT NOT NULL DEFAULT 'open',
  report_count   INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL,
  deleted_at     INTEGER,
  FOREIGN KEY (author_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS bottle_replies (
  reply_id      TEXT PRIMARY KEY,
  bottle_id     TEXT NOT NULL UNIQUE,
  from_user_id  TEXT NOT NULL,
  message       TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'visible',
  created_at    INTEGER NOT NULL,
  FOREIGN KEY (bottle_id) REFERENCES stress_bottles(bottle_id) ON DELETE CASCADE,
  FOREIGN KEY (from_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS moderation_reports (
  report_id       TEXT PRIMARY KEY,
  reporter_user_id TEXT NOT NULL,
  target_type     TEXT NOT NULL,
  target_id       TEXT NOT NULL,
  reason          TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'open',
  resolution      TEXT,
  reviewer_note   TEXT,
  reviewed_at     INTEGER,
  created_at      INTEGER NOT NULL,
  FOREIGN KEY (reporter_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_blocks (
  user_id         TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at      INTEGER NOT NULL,
  PRIMARY KEY (user_id, blocked_user_id),
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (blocked_user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Phase 2: 全量数据上传 ---
-- stress_history: 每次 stress 更新 append 一条,用于趋势曲线 / AI 分析
CREATE TABLE IF NOT EXISTS stress_history (
  history_id    INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       TEXT NOT NULL,
  score         INTEGER NOT NULL,
  level         TEXT NOT NULL,
  recorded_at   INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- hrv_samples: HealthKit HRV 样本(每天 10-100 条)
CREATE TABLE IF NOT EXISTS hrv_samples (
  sample_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       TEXT NOT NULL,
  value_ms      REAL NOT NULL,
  source        TEXT,
  measured_at   INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- breathing_sessions: 呼吸训练 session
CREATE TABLE IF NOT EXISTS breathing_sessions (
  session_id    TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  pattern       TEXT NOT NULL,            -- "coherent"/"fourSevenEight"/"box"/"resonant"/etc
  minutes       INTEGER NOT NULL,
  completed_at  INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- meditation_sessions: 冥想 session
CREATE TABLE IF NOT EXISTS meditation_sessions (
  session_id    TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  minutes       INTEGER NOT NULL,
  completed_at  INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- daily_summary: 每用户每天 1 条(server cron 聚合 + client 兜底 upsert)
CREATE TABLE IF NOT EXISTS daily_summary (
  user_id              TEXT NOT NULL,
  date                 TEXT NOT NULL,          -- "YYYY-MM-DD",用户本地时区
  stress_avg           REAL,
  stress_max           INTEGER,
  stress_min           INTEGER,
  stress_high_minutes  INTEGER,
  hrv_avg              REAL,
  breathing_count      INTEGER DEFAULT 0,
  breathing_minutes    INTEGER DEFAULT 0,
  meditation_count     INTEGER DEFAULT 0,
  meditation_minutes   INTEGER DEFAULT 0,
  updated_at           INTEGER NOT NULL,
  PRIMARY KEY (user_id, date),
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- 用户偏好(per-user):分享训练 session 给好友看 等开关
CREATE TABLE IF NOT EXISTS user_share_prefs (
  user_id            TEXT PRIMARY KEY,
  share_stress       INTEGER NOT NULL DEFAULT 1,    -- 跟原 sharingMyStress 一致
  share_training     INTEGER NOT NULL DEFAULT 0,    -- 默认 off,用户主动开
  share_hrv          INTEGER NOT NULL DEFAULT 0,    -- 健康数据出设备必须单独 opt-in
  updated_at         INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS schema_migrations (
  migration_id TEXT PRIMARY KEY,
  applied_at   INTEGER NOT NULL
);
`);

// --- 步骤 2:ALTER 老表加新列(在 CREATE INDEX 之前,顺序很重要 ——
// 之前历史上 CREATE INDEX(public_id) 排在 ALTER 之前,导致 service 几次启动失败)

const alterSafe = (sql, label) => {
  try {
    db.exec(sql);
  } catch (e) {
    if (!String(e.message).toLowerCase().includes('duplicate')) {
      console.error(`[migration] ${label} failed:`, e.message);
    }
  }
};

alterSafe(`ALTER TABLE users ADD COLUMN public_id TEXT`, 'ALTER users add public_id');
alterSafe(`ALTER TABLE friend_requests ADD COLUMN is_reverse INTEGER NOT NULL DEFAULT 0`, 'ALTER friend_requests add is_reverse');
// Algorithm versioning(v2: z-score + circadian + phasic):新旧算法分线
alterSafe(`ALTER TABLE stress_history ADD COLUMN algorithm_version INTEGER NOT NULL DEFAULT 1`, 'ALTER stress_history add algorithm_version');
alterSafe(`ALTER TABLE stress_snapshots ADD COLUMN algorithm_version INTEGER NOT NULL DEFAULT 1`, 'ALTER stress_snapshots add algorithm_version');
alterSafe(`ALTER TABLE care_events ADD COLUMN reply_to_event_id TEXT`, 'ALTER care_events add reply_to_event_id');
alterSafe(`ALTER TABLE bottle_replies ADD COLUMN status TEXT NOT NULL DEFAULT 'visible'`, 'ALTER bottle_replies add status');
alterSafe(`ALTER TABLE moderation_reports ADD COLUMN status TEXT NOT NULL DEFAULT 'open'`, 'ALTER moderation_reports add status');
alterSafe(`ALTER TABLE moderation_reports ADD COLUMN resolution TEXT`, 'ALTER moderation_reports add resolution');
alterSafe(`ALTER TABLE moderation_reports ADD COLUMN reviewer_note TEXT`, 'ALTER moderation_reports add reviewer_note');
alterSafe(`ALTER TABLE moderation_reports ADD COLUMN reviewed_at INTEGER`, 'ALTER moderation_reports add reviewed_at');

// 旧客户端曾把 HRV server 同步默认开启,但引导页没有明确披露。
// 一次性撤回旧默认并清理已上传值;之后只有用户在共振设置主动开启才可重新上传。
{
  const migrationId = '20260913_hrv_explicit_opt_in';
  const applied = db.prepare('SELECT 1 FROM schema_migrations WHERE migration_id = ?').get(migrationId);
  if (!applied) {
    const migrate = db.transaction(() => {
      const t = Date.now();
      db.prepare('UPDATE user_share_prefs SET share_hrv = 0, updated_at = ?').run(t);
      db.prepare('DELETE FROM hrv_samples').run();
      db.prepare('UPDATE daily_summary SET hrv_avg = NULL, updated_at = ?').run(t);
      db.prepare('INSERT INTO schema_migrations (migration_id, applied_at) VALUES (?, ?)').run(migrationId, t);
    });
    migrate();
  }
}

// --- 步骤 3:CREATE INDEX(失败只 log,不让 service 起不来 —— 索引能晚后再补,但 service 不能挂)

const indexSafe = (sql, label) => {
  try {
    db.exec(sql);
  } catch (e) {
    console.error(`[migration] CREATE INDEX ${label} failed:`, e.message);
  }
};

indexSafe(`CREATE INDEX IF NOT EXISTS idx_users_email_hash ON users(email_hash)`, 'idx_users_email_hash');
indexSafe(`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_public_id ON users(public_id)`, 'idx_users_public_id');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id)`, 'idx_devices_user_id');
indexSafe(`CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_token ON devices(apns_token)`, 'idx_devices_token');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_freqs_to ON friend_requests(to_user_id, status)`, 'idx_freqs_to');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_freqs_from ON friend_requests(from_user_id, status)`, 'idx_freqs_from');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_invites_to_email_hash ON invites(to_email_hash)`, 'idx_invites_to_email_hash');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_invites_status ON invites(status)`, 'idx_invites_status');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_friend_mutes_user ON friend_mutes(user_id)`, 'idx_friend_mutes_user');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_care_events_to ON care_events(to_user_id, created_at)`, 'idx_care_events_to');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_care_events_from ON care_events(from_user_id, created_at)`, 'idx_care_events_from');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_care_events_reply ON care_events(reply_to_event_id)`, 'idx_care_events_reply');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_stress_snapshots_updated ON stress_snapshots(updated_at)`, 'idx_stress_snapshots_updated');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_stress_bottles_open ON stress_bottles(status, expires_at, created_at)`, 'idx_stress_bottles_open');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_stress_bottles_author ON stress_bottles(author_user_id, created_at)`, 'idx_stress_bottles_author');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_bottle_replies_bottle ON bottle_replies(bottle_id)`, 'idx_bottle_replies_bottle');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_reports_target ON moderation_reports(target_type, target_id)`, 'idx_reports_target');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_reports_status_created ON moderation_reports(status, created_at)`, 'idx_reports_status_created');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_user_blocks_user ON user_blocks(user_id)`, 'idx_user_blocks_user');

// Phase 2 indexes
indexSafe(`CREATE INDEX IF NOT EXISTS idx_stress_history_user_time ON stress_history(user_id, recorded_at)`, 'idx_stress_history_user_time');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_hrv_samples_user_time ON hrv_samples(user_id, measured_at)`, 'idx_hrv_samples_user_time');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_breathing_user_time ON breathing_sessions(user_id, completed_at)`, 'idx_breathing_user_time');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_meditation_user_time ON meditation_sessions(user_id, completed_at)`, 'idx_meditation_user_time');
indexSafe(`CREATE INDEX IF NOT EXISTS idx_daily_summary_date ON daily_summary(date)`, 'idx_daily_summary_date');

// 回填:给没有 public_id 的现有 user 生成
{
  const usersWithoutPublicId = db.prepare('SELECT user_id FROM users WHERE public_id IS NULL').all();
  const ins = db.prepare('UPDATE users SET public_id = ? WHERE user_id = ?');
  for (const u of usersWithoutPublicId) {
    ins.run(generatePublicId(), u.user_id);
  }
}

// --- Helpers

export function now() { return Date.now(); }

/// 6 位字母数字密友 ID,排除易混 0/O/1/I/L
export function generatePublicId() {
  const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  let attempts = 0;
  while (attempts < 10) {
    let id = '';
    for (let i = 0; i < 6; i++) {
      id += alphabet[Math.floor(Math.random() * alphabet.length)];
    }
    const exists = db.prepare('SELECT 1 FROM users WHERE public_id = ?').get(id);
    if (!exists) return id;
    attempts++;
  }
  // 极小概率全部碰撞,加 1 位
  return generatePublicId() + alphabet[Math.floor(Math.random() * alphabet.length)];
}

export function upsertUser({ userId, appleSub, emailHash, displayName }) {
  const existing = db.prepare('SELECT * FROM users WHERE apple_sub = ?').get(appleSub);
  const t = now();
  if (existing) {
    db.prepare(`
      UPDATE users SET email_hash = COALESCE(?, email_hash),
                       display_name = COALESCE(?, display_name),
                       updated_at = ?
      WHERE user_id = ?
    `).run(emailHash || null, displayName || null, t, existing.user_id);
    return db.prepare('SELECT * FROM users WHERE user_id = ?').get(existing.user_id);
  }
  db.prepare(`
    INSERT INTO users (user_id, apple_sub, email_hash, display_name, public_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(userId, appleSub, emailHash || null, displayName || null, generatePublicId(), t, t);
  return db.prepare('SELECT * FROM users WHERE user_id = ?').get(userId);
}

export function findUserByEmailHash(emailHash) {
  return db.prepare('SELECT * FROM users WHERE email_hash = ?').get(emailHash);
}

export function findUserByPublicId(publicId) {
  if (!publicId) return null;
  return db.prepare('SELECT * FROM users WHERE public_id = ?').get(publicId.toUpperCase());
}

export function getUser(userId) {
  return db.prepare('SELECT * FROM users WHERE user_id = ?').get(userId);
}

export function upsertDevice({ deviceId, userId, apnsToken }) {
  const t = now();
  // 同 token 可能重新注册到不同 user(换 Apple ID),覆盖
  db.prepare(`
    INSERT INTO devices (device_id, user_id, apns_token, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(device_id) DO UPDATE SET
      user_id = excluded.user_id,
      apns_token = excluded.apns_token,
      updated_at = excluded.updated_at
  `).run(deviceId, userId, apnsToken, t, t);
  return db.prepare('SELECT * FROM devices WHERE device_id = ?').get(deviceId);
}

export function getDevicesForUser(userId) {
  return db.prepare('SELECT * FROM devices WHERE user_id = ?').all(userId);
}

export function deleteDevice({ deviceId, userId }) {
  if (!deviceId || !userId) return false;
  const result = db.prepare(`
    DELETE FROM devices
    WHERE device_id = ? AND user_id = ?
  `).run(deviceId, userId);
  return result.changes > 0;
}

export function createInvite({ inviteId, code, fromUserId, toEmailHash, shareUrl, ttlHours }) {
  const t = now();
  const exp = t + ttlHours * 3600 * 1000;
  db.prepare(`
    INSERT INTO invites (invite_id, invite_code, from_user_id, to_email_hash, share_url,
                         status, created_at, expires_at)
    VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
  `).run(inviteId, code, fromUserId, toEmailHash || null, shareUrl, t, exp);
  return db.prepare('SELECT * FROM invites WHERE invite_id = ?').get(inviteId);
}

export function findInviteByCode(code) {
  return db.prepare(`
    SELECT * FROM invites
    WHERE invite_code = ? AND status = 'pending' AND expires_at > ?
  `).get(code, now());
}

export function getInboxInvites(emailHash) {
  return db.prepare(`
    SELECT i.*, u.display_name AS from_display_name
    FROM invites i
    JOIN users u ON i.from_user_id = u.user_id
    WHERE i.to_email_hash = ? AND i.status = 'pending' AND i.expires_at > ?
    ORDER BY i.created_at DESC
  `).all(emailHash, now());
}

export function acceptInvite({ inviteId, userId }) {
  const t = now();
  const result = db.prepare(`
    UPDATE invites
    SET status = 'accepted', accepted_at = ?, accepted_by = ?
    WHERE invite_id = ? AND status = 'pending' AND expires_at > ?
  `).run(t, userId, inviteId, t);
  return result.changes > 0;
}

export function recordFriendship(userIdA, userIdB) {
  const [a, b] = [userIdA, userIdB].sort();
  if (a === b) return;
  db.prepare(`
    INSERT INTO friendships (user_id_a, user_id_b, created_at)
    VALUES (?, ?, ?)
    ON CONFLICT(user_id_a, user_id_b) DO UPDATE SET
      created_at = excluded.created_at
  `).run(a, b, now());
}

export function deleteFriendship(userIdA, userIdB) {
  const [a, b] = [userIdA, userIdB].sort();
  db.prepare('DELETE FROM friendships WHERE user_id_a = ? AND user_id_b = ?').run(a, b);
  db.prepare(`
    DELETE FROM friend_mutes
    WHERE (user_id = ? AND muted_user_id = ?)
       OR (user_id = ? AND muted_user_id = ?)
  `).run(userIdA, userIdB, userIdB, userIdA);
}

export function getFriendsForUser(userId) {
  return db.prepare(`
    SELECT u.user_id, u.public_id, u.display_name
    FROM friendships f
    JOIN users u ON u.user_id = CASE
      WHEN f.user_id_a = ? THEN f.user_id_b
      ELSE f.user_id_a
    END
    WHERE f.user_id_a = ? OR f.user_id_b = ?
    ORDER BY f.created_at DESC
  `).all(userId, userId, userId);
}

export function setFriendMute({ userId, mutedUserId, muted }) {
  if (userId === mutedUserId) return false;
  if (muted) {
    db.prepare(`
      INSERT OR IGNORE INTO friend_mutes (user_id, muted_user_id, created_at)
      VALUES (?, ?, ?)
    `).run(userId, mutedUserId, now());
    return true;
  }
  db.prepare(`
    DELETE FROM friend_mutes
    WHERE user_id = ? AND muted_user_id = ?
  `).run(userId, mutedUserId);
  return true;
}

export function isFriendMuted(userId, mutedUserId) {
  if (!userId || !mutedUserId) return false;
  return !!db.prepare(`
    SELECT 1 FROM friend_mutes
    WHERE user_id = ? AND muted_user_id = ?
  `).get(userId, mutedUserId);
}

export function createCareEvent({ eventId, fromUserId, toUserId, type, message, payloadJSON, replyToEventId = null }) {
  const t = now();
  db.prepare(`
    INSERT INTO care_events (
      event_id, from_user_id, to_user_id, type, message, payload_json, reply_to_event_id, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(eventId, fromUserId, toUserId, type, message || null, payloadJSON || null, replyToEventId, t);
  return db.prepare('SELECT * FROM care_events WHERE event_id = ?').get(eventId);
}

export function getCareEvent(eventId) {
  if (!eventId) return null;
  return db.prepare('SELECT * FROM care_events WHERE event_id = ?').get(eventId) || null;
}

export function getInboxCareEvents(userId, limit = 80) {
  return db.prepare(`
    SELECT e.*,
           u.display_name AS from_display_name,
           u.public_id    AS from_public_id
    FROM care_events e
    JOIN users u ON e.from_user_id = u.user_id
    WHERE e.to_user_id = ?
    ORDER BY e.created_at DESC
    LIMIT ?
  `).all(userId, limit);
}

export function getCareEventTimeline(userId, friendUserId = null, limit = 80) {
  const friendFilter = friendUserId
    ? `AND ((e.from_user_id = @userId AND e.to_user_id = @friendUserId)
             OR (e.from_user_id = @friendUserId AND e.to_user_id = @userId))`
    : '';
  return db.prepare(`
    SELECT e.*,
           fu.display_name AS from_display_name,
           fu.public_id    AS from_public_id,
           tu.display_name AS to_display_name,
           tu.public_id    AS to_public_id
    FROM care_events e
    JOIN users fu ON e.from_user_id = fu.user_id
    JOIN users tu ON e.to_user_id = tu.user_id
    WHERE (e.from_user_id = @userId OR e.to_user_id = @userId)
      ${friendFilter}
    ORDER BY e.created_at DESC
    LIMIT @limit
  `).all({ userId, friendUserId, limit });
}

export function markCareEventsRead(userId, eventIds = null) {
  const readAt = now();
  if (Array.isArray(eventIds)) {
    const ids = [...new Set(eventIds.filter(id => typeof id === 'string' && id.length > 0 && id.length <= 80))].slice(0, 120);
    if (ids.length === 0) return { changes: 0, readAt };
    const placeholders = ids.map(() => '?').join(',');
    const result = db.prepare(`
      UPDATE care_events
      SET read_at = COALESCE(read_at, ?)
      WHERE to_user_id = ? AND read_at IS NULL AND event_id IN (${placeholders})
    `).run(readAt, userId, ...ids);
    return { changes: result.changes, readAt };
  }
  const result = db.prepare(`
    UPDATE care_events
    SET read_at = COALESCE(read_at, ?)
    WHERE to_user_id = ? AND read_at IS NULL
  `).run(readAt, userId);
  return { changes: result.changes, readAt };
}

export function deleteCareEvent({ eventId, userId }) {
  const result = db.prepare(`
    DELETE FROM care_events
    WHERE event_id = ? AND to_user_id = ?
  `).run(eventId, userId);
  return result.changes > 0;
}

export function upsertStressSnapshot({ userId, score, level, displayName }) {
  const t = now();
  db.prepare(`
    INSERT INTO stress_snapshots (user_id, score, level, display_name, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET
      score = excluded.score,
      level = excluded.level,
      display_name = excluded.display_name,
      updated_at = excluded.updated_at
  `).run(userId, score, level, displayName || null, t);
  return db.prepare('SELECT * FROM stress_snapshots WHERE user_id = ?').get(userId);
}

export function deleteStressSnapshot(userId) {
  db.prepare('DELETE FROM stress_snapshots WHERE user_id = ?').run(userId);
}

export function getFriendStressSnapshots(userId) {
  return db.prepare(`
    SELECT u.user_id,
           u.public_id,
           u.display_name AS user_display_name,
           s.score,
           s.level,
           s.display_name AS stress_display_name,
           s.updated_at,
           f.created_at AS friendship_created_at
    FROM friendships f
    JOIN users u ON u.user_id = CASE
      WHEN f.user_id_a = ? THEN f.user_id_b
      ELSE f.user_id_a
    END
    LEFT JOIN stress_snapshots s ON s.user_id = u.user_id
    WHERE f.user_id_a = ? OR f.user_id_b = ?
    ORDER BY COALESCE(s.updated_at, f.created_at) DESC
  `).all(userId, userId, userId);
}

export function deleteUser(userId) {
  // CASCADE 会自动删 devices / invites / friend_requests / friendships
  db.prepare('DELETE FROM users WHERE user_id = ?').run(userId);
}

// MARK: - Stress bottles

export function countUserBottlesSince(userId, sinceTs) {
  return db.prepare(`
    SELECT COUNT(*) AS count
    FROM stress_bottles
    WHERE author_user_id = ? AND created_at >= ? AND deleted_at IS NULL
  `).get(userId, sinceTs)?.count || 0;
}

export function createStressBottle({
  bottleId,
  authorUserId,
  moodTag,
  stressScore,
  stressLevel,
  message,
  anonymous,
  ttlHours,
}) {
  const t = now();
  const exp = t + ttlHours * 3600 * 1000;
  db.prepare(`
    INSERT INTO stress_bottles (
      bottle_id, author_user_id, mood_tag, stress_score, stress_level,
      message, anonymous, status, created_at, expires_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?, ?)
  `).run(
    bottleId,
    authorUserId,
    moodTag,
    stressScore == null ? null : stressScore,
    stressLevel || null,
    message,
    anonymous ? 1 : 0,
    t,
    exp
  );
  return getStressBottleForUser({ bottleId, viewerUserId: authorUserId, includeOwn: true });
}

export function getStressBottleForUser({ bottleId, viewerUserId, includeOwn = false }) {
  const row = db.prepare(`
    SELECT b.*,
           u.display_name AS author_display_name,
           r.reply_id,
           r.from_user_id AS reply_from_user_id,
           r.message AS reply_message,
           r.created_at AS reply_created_at,
           ru.display_name AS reply_from_display_name
    FROM stress_bottles b
    JOIN users u ON u.user_id = b.author_user_id
    LEFT JOIN bottle_replies r ON r.bottle_id = b.bottle_id AND r.status = 'visible'
    LEFT JOIN users ru ON ru.user_id = r.from_user_id
    WHERE b.bottle_id = ?
      AND b.deleted_at IS NULL
      AND (? OR b.author_user_id != ?)
      AND NOT EXISTS (
        SELECT 1 FROM user_blocks ub
        WHERE (ub.user_id = ? AND ub.blocked_user_id = b.author_user_id)
           OR (ub.user_id = b.author_user_id AND ub.blocked_user_id = ?)
      )
  `).get(bottleId, includeOwn ? 1 : 0, viewerUserId, viewerUserId, viewerUserId);
  return row || null;
}

export function getSeaStressBottles({ viewerUserId, limit }) {
  return db.prepare(`
    SELECT b.*,
           u.display_name AS author_display_name,
           r.reply_id,
           r.from_user_id AS reply_from_user_id,
           r.message AS reply_message,
           r.created_at AS reply_created_at,
           ru.display_name AS reply_from_display_name
    FROM stress_bottles b
    JOIN users u ON u.user_id = b.author_user_id
    LEFT JOIN bottle_replies r ON r.bottle_id = b.bottle_id AND r.status = 'visible'
    LEFT JOIN users ru ON ru.user_id = r.from_user_id
    WHERE b.status = 'open'
      AND b.expires_at > ?
      AND b.deleted_at IS NULL
      AND b.author_user_id != ?
      AND b.report_count < 3
      AND NOT EXISTS (
        SELECT 1 FROM user_blocks ub
        WHERE (ub.user_id = ? AND ub.blocked_user_id = b.author_user_id)
           OR (ub.user_id = b.author_user_id AND ub.blocked_user_id = ?)
      )
      AND NOT EXISTS (
        SELECT 1 FROM moderation_reports mr
        WHERE mr.reporter_user_id = ?
          AND mr.target_type = 'bottle'
          AND mr.target_id = b.bottle_id
      )
    ORDER BY RANDOM()
    LIMIT ?
  `).all(now(), viewerUserId, viewerUserId, viewerUserId, viewerUserId, limit);
}

export function getMyStressBottles({ userId, limit }) {
  return db.prepare(`
    SELECT b.*,
           u.display_name AS author_display_name,
           r.reply_id,
           r.from_user_id AS reply_from_user_id,
           r.message AS reply_message,
           r.created_at AS reply_created_at,
           ru.display_name AS reply_from_display_name
    FROM stress_bottles b
    JOIN users u ON u.user_id = b.author_user_id
    LEFT JOIN bottle_replies r ON r.bottle_id = b.bottle_id AND r.status = 'visible'
    LEFT JOIN users ru ON ru.user_id = r.from_user_id
    WHERE b.author_user_id = ?
      AND b.deleted_at IS NULL
    ORDER BY b.created_at DESC
    LIMIT ?
  `).all(userId, limit);
}

export function replyToStressBottle({ replyId, bottleId, fromUserId, message }) {
  const bottle = db.prepare(`
    SELECT * FROM stress_bottles
    WHERE bottle_id = ?
      AND deleted_at IS NULL
      AND status = 'open'
      AND expires_at > ?
  `).get(bottleId, now());
  if (!bottle || bottle.author_user_id === fromUserId) return null;

  const blocked = db.prepare(`
    SELECT 1 FROM user_blocks
    WHERE (user_id = ? AND blocked_user_id = ?)
       OR (user_id = ? AND blocked_user_id = ?)
  `).get(fromUserId, bottle.author_user_id, bottle.author_user_id, fromUserId);
  if (blocked) return null;

  const t = now();
  const tx = db.transaction(() => {
    db.prepare(`
      INSERT INTO bottle_replies (reply_id, bottle_id, from_user_id, message, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(replyId, bottleId, fromUserId, message, t);
    db.prepare(`
      UPDATE stress_bottles
      SET status = 'replied'
      WHERE bottle_id = ?
    `).run(bottleId);
  });
  tx();
  return db.prepare('SELECT * FROM bottle_replies WHERE reply_id = ?').get(replyId);
}

export function getBottleReplyForOwner({ bottleId, ownerUserId }) {
  return db.prepare(`
    SELECT r.*, b.author_user_id
    FROM bottle_replies r
    JOIN stress_bottles b ON b.bottle_id = r.bottle_id
    WHERE r.bottle_id = ? AND b.author_user_id = ? AND b.deleted_at IS NULL
  `).get(bottleId, ownerUserId) || null;
}

export function hideBottleReplyForOwner({ bottleId, ownerUserId }) {
  const reply = getBottleReplyForOwner({ bottleId, ownerUserId });
  if (!reply) return null;
  db.prepare(`UPDATE bottle_replies SET status = 'hidden' WHERE reply_id = ?`).run(reply.reply_id);
  return reply;
}

export function createModerationReport({ reportId, reporterUserId, targetType, targetId, reason }) {
  // 网络重试或重复点击按“同一用户 + 同一目标”幂等处理,避免一人把瓶子刷到自动隐藏。
  const existing = db.prepare(`
    SELECT * FROM moderation_reports
    WHERE reporter_user_id = ? AND target_type = ? AND target_id = ?
    ORDER BY created_at DESC
    LIMIT 1
  `).get(reporterUserId, targetType, targetId);
  if (existing) return existing;

  const t = now();
  db.prepare(`
    INSERT INTO moderation_reports (
      report_id, reporter_user_id, target_type, target_id, reason, status, created_at
    )
    VALUES (?, ?, ?, ?, ?, 'open', ?)
  `).run(reportId, reporterUserId, targetType, targetId, reason, t);

  if (targetType === 'bottle') {
    db.prepare(`
      UPDATE stress_bottles
      SET report_count = report_count + 1,
          status = CASE WHEN report_count + 1 >= 3 THEN 'hidden' ELSE status END
      WHERE bottle_id = ?
    `).run(targetId);
  }
  return db.prepare('SELECT * FROM moderation_reports WHERE report_id = ?').get(reportId);
}

export function blockUser({ userId, blockedUserId }) {
  if (!userId || !blockedUserId || userId === blockedUserId) return false;
  db.prepare(`
    INSERT OR IGNORE INTO user_blocks (user_id, blocked_user_id, created_at)
    VALUES (?, ?, ?)
  `).run(userId, blockedUserId, now());
  return true;
}

export function deleteStressBottle({ bottleId, userId }) {
  const result = db.prepare(`
    UPDATE stress_bottles
    SET deleted_at = ?, status = 'deleted'
    WHERE bottle_id = ? AND author_user_id = ? AND deleted_at IS NULL
  `).run(now(), bottleId, userId);
  return result.changes > 0;
}

export function listModerationReports({ limit = 100, status = 'open' }) {
  const selectedStatus = ['open', 'resolved', 'all'].includes(status) ? status : 'open';
  return db.prepare(`
    SELECT r.*,
           reporter.display_name AS reporter_display_name,
           b.message AS bottle_message,
           b.mood_tag AS bottle_mood_tag,
           b.status AS bottle_status,
           b.report_count AS bottle_report_count,
           author.display_name AS bottle_author_display_name,
           br.message AS reply_message,
           br.status AS reply_status,
           reply_author.display_name AS reply_author_display_name
    FROM moderation_reports r
    LEFT JOIN users reporter ON reporter.user_id = r.reporter_user_id
    LEFT JOIN stress_bottles b ON r.target_type = 'bottle' AND b.bottle_id = r.target_id
    LEFT JOIN users author ON author.user_id = b.author_user_id
    LEFT JOIN bottle_replies br ON r.target_type = 'reply' AND br.reply_id = r.target_id
    LEFT JOIN users reply_author ON reply_author.user_id = br.from_user_id
    WHERE (? = 'all' OR r.status = ?)
    ORDER BY r.created_at DESC
    LIMIT ?
  `).all(selectedStatus, selectedStatus, limit);
}

export function resolveModerationReport({ reportId, action, reviewerNote = '' }) {
  if (!['hide', 'restore', 'dismiss'].includes(action)) return null;
  const report = db.prepare(`
    SELECT * FROM moderation_reports WHERE report_id = ?
  `).get(reportId);
  if (!report) return null;

  const reviewedAt = now();
  const tx = db.transaction(() => {
    if (report.target_type === 'bottle' && action === 'hide') {
      db.prepare(`
        UPDATE stress_bottles SET status = 'hidden'
        WHERE bottle_id = ? AND deleted_at IS NULL
      `).run(report.target_id);
    } else if (report.target_type === 'bottle' && action === 'restore') {
      db.prepare(`
        UPDATE stress_bottles SET status = 'open'
        WHERE bottle_id = ? AND deleted_at IS NULL AND status = 'hidden' AND expires_at > ?
      `).run(report.target_id, reviewedAt);
    } else if (report.target_type === 'reply' && action === 'hide') {
      db.prepare(`UPDATE bottle_replies SET status = 'hidden' WHERE reply_id = ?`).run(report.target_id);
    } else if (report.target_type === 'reply' && action === 'restore') {
      db.prepare(`UPDATE bottle_replies SET status = 'visible' WHERE reply_id = ?`).run(report.target_id);
    }

    // 同一目标可能被多人举报;一次审核结论同时关闭该目标的所有待处理报告。
    db.prepare(`
      UPDATE moderation_reports
      SET status = 'resolved', resolution = ?, reviewer_note = ?, reviewed_at = ?
      WHERE target_type = ? AND target_id = ? AND status = 'open'
    `).run(action, reviewerNote, reviewedAt, report.target_type, report.target_id);
  });
  tx();

  return db.prepare(`
    SELECT r.*,
           reporter.display_name AS reporter_display_name,
           b.message AS bottle_message,
           b.mood_tag AS bottle_mood_tag,
           b.status AS bottle_status,
           b.report_count AS bottle_report_count,
           author.display_name AS bottle_author_display_name,
           br.message AS reply_message,
           br.status AS reply_status,
           reply_author.display_name AS reply_author_display_name
    FROM moderation_reports r
    LEFT JOIN users reporter ON reporter.user_id = r.reporter_user_id
    LEFT JOIN stress_bottles b ON r.target_type = 'bottle' AND b.bottle_id = r.target_id
    LEFT JOIN users author ON author.user_id = b.author_user_id
    LEFT JOIN bottle_replies br ON r.target_type = 'reply' AND br.reply_id = r.target_id
    LEFT JOIN users reply_author ON reply_author.user_id = br.from_user_id
    WHERE r.report_id = ?
  `).get(reportId) || null;
}

export function setStressBottleStatus({ bottleId, status }) {
  const result = db.prepare(`
    UPDATE stress_bottles
    SET status = ?
    WHERE bottle_id = ? AND deleted_at IS NULL
  `).run(status, bottleId);
  return result.changes > 0;
}

// MARK: - Friend requests

export function createFriendRequest({ requestId, fromUserId, toUserId, shareUrl, ttlHours, isReverse = false }) {
  const t = now();
  const exp = t + ttlHours * 3600 * 1000;
  // 同方向已有 pending 请求 → 替换
  db.prepare(`
    UPDATE friend_requests SET status = 'cancelled', acted_at = ?
    WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'
  `).run(t, fromUserId, toUserId);
  db.prepare(`
    INSERT INTO friend_requests (request_id, from_user_id, to_user_id, share_url,
                                 status, is_reverse, created_at, expires_at)
    VALUES (?, ?, ?, ?, 'pending', ?, ?, ?)
  `).run(requestId, fromUserId, toUserId, shareUrl, isReverse ? 1 : 0, t, exp);
  return db.prepare('SELECT * FROM friend_requests WHERE request_id = ?').get(requestId);
}

export function areFriends(userIdA, userIdB) {
  const [a, b] = [userIdA, userIdB].sort();
  if (a === b) return false;
  return !!db.prepare(
    'SELECT 1 FROM friendships WHERE user_id_a = ? AND user_id_b = ?'
  ).get(a, b);
}

export function getInboxRequests(toUserId) {
  return db.prepare(`
    SELECT r.*,
           r.is_reverse   AS is_reverse,
           u.display_name AS from_display_name,
           u.public_id    AS from_public_id
    FROM friend_requests r
    JOIN users u ON r.from_user_id = u.user_id
    WHERE r.to_user_id = ? AND r.status = 'pending' AND r.expires_at > ?
    ORDER BY r.created_at DESC
  `).all(toUserId, now());
}

export function getOutgoingRequests(fromUserId) {
  return db.prepare(`
    SELECT r.*,
           r.is_reverse   AS is_reverse,
           u.display_name AS to_display_name,
           u.public_id    AS to_public_id
    FROM friend_requests r
    JOIN users u ON r.to_user_id = u.user_id
    WHERE r.from_user_id = ? AND r.status = 'pending' AND r.expires_at > ?
    ORDER BY r.created_at DESC
  `).all(fromUserId, now());
}

export function getFriendRequest(requestId) {
  return db.prepare('SELECT * FROM friend_requests WHERE request_id = ?').get(requestId);
}

export function actOnFriendRequest({ requestId, userId, status }) {
  // status: 'accepted' / 'declined' / 'cancelled'
  const t = now();
  const result = db.prepare(`
    UPDATE friend_requests
    SET status = ?,
        acted_at = ?,
        share_url = CASE WHEN ? = 'accepted' THEN '' ELSE share_url END
    WHERE request_id = ?
      AND to_user_id = ?
      AND status = 'pending'
      AND expires_at > ?
  `).run(status, t, status, requestId, userId, now());
  return result.changes > 0;
}

export function cancelOutgoingFriendRequest({ requestId, fromUserId }) {
  const result = db.prepare(`
    UPDATE friend_requests
    SET status = 'cancelled', acted_at = ?
    WHERE request_id = ? AND from_user_id = ? AND status = 'pending'
  `).run(now(), requestId, fromUserId);
  return result.changes > 0;
}

/// 清理过期数据,防止表无限增长
///   - friend_requests / invites:未接受请求过期 30d 后删;已接受记录处理 30d 后删
///   - stress_bottles:expires_at < now 且仍 open → soft delete (status='expired')
///   - stress_bottles 已 soft delete > 90 天 → 物理删(连同 replies 级联)
///   - care_events:created_at < now - 30d → 物理删(关怀事件不需要长期保留)
///   - moderation_reports:created_at < now - 180d → 物理删
export function pruneExpiredRequests() {
  const cutoff30 = now() - 30 * 86400_000;
  const cutoff90 = now() - 90 * 86400_000;
  const cutoff180 = now() - 180 * 86400_000;

  const fr = db.prepare(`
    DELETE FROM friend_requests
    WHERE (status = 'accepted' AND acted_at IS NOT NULL AND acted_at < ?)
       OR (status != 'accepted' AND expires_at < ?)
  `).run(cutoff30, cutoff30);

  const inv = db.prepare(`
    DELETE FROM invites
    WHERE (status = 'accepted' AND accepted_at IS NOT NULL AND accepted_at < ?)
       OR (status != 'accepted' AND expires_at < ?)
  `).run(cutoff30, cutoff30);

  // bottles 阶段 1:过期但还没标 expired 的,标 expired
  const bottlesSoft = db.prepare(`
    UPDATE stress_bottles
    SET status = 'expired', deleted_at = COALESCE(deleted_at, ?)
    WHERE expires_at < ? AND deleted_at IS NULL AND status = 'open'
  `).run(now(), now());

  // bottles 阶段 2:soft delete 后超 90 天,物理删
  const bottlesHard = db.prepare(`
    DELETE FROM stress_bottles
    WHERE deleted_at IS NOT NULL AND deleted_at < ?
  `).run(cutoff90);

  // care_events 30 天后物理删(心跳/邀请/告警之类,过了就过了)
  const careEvents = db.prepare(`
    DELETE FROM care_events
    WHERE created_at < ?
  `).run(cutoff30);

  // moderation_reports 180 天后物理删(合规留档半年够了)
  const reports = db.prepare(`
    DELETE FROM moderation_reports
    WHERE created_at < ?
  `).run(cutoff180);

  return {
    friendRequests: fr.changes,
    invites: inv.changes,
    bottlesSoft: bottlesSoft.changes,
    bottlesHard: bottlesHard.changes,
    careEvents: careEvents.changes,
    reports: reports.changes,
  };
}

// ============================================================
// Phase 2: 全量数据上传 helpers
// ============================================================

// --- stress_history ---

export function appendStressHistory({ userId, score, level, recordedAt, algorithmVersion }) {
  db.prepare(`
    INSERT INTO stress_history (user_id, score, level, recorded_at, algorithm_version)
    VALUES (?, ?, ?, ?, ?)
  `).run(userId, score, level, recordedAt || now(), algorithmVersion || 1);
}

export function getStressHistory({ userId, sinceTs, untilTs, limit = 5000 }) {
  return db.prepare(`
    SELECT history_id, score, level, recorded_at, algorithm_version
    FROM stress_history
    WHERE user_id = ? AND recorded_at >= ? AND recorded_at <= ?
    ORDER BY recorded_at ASC
    LIMIT ?
  `).all(userId, sinceTs, untilTs, limit);
}

// --- hrv_samples ---

export function appendHRVSamples({ userId, samples }) {
  if (!samples || samples.length === 0) return 0;
  const stmt = db.prepare(`
    INSERT INTO hrv_samples (user_id, value_ms, source, measured_at)
    VALUES (?, ?, ?, ?)
  `);
  const tx = db.transaction((rows) => {
    for (const r of rows) {
      stmt.run(userId, r.valueMs, r.source || null, r.measuredAt);
    }
  });
  tx(samples);
  return samples.length;
}

export function getHRVHistory({ userId, sinceTs, untilTs, limit = 5000 }) {
  return db.prepare(`
    SELECT sample_id, value_ms, source, measured_at
    FROM hrv_samples
    WHERE user_id = ? AND measured_at >= ? AND measured_at <= ?
    ORDER BY measured_at ASC
    LIMIT ?
  `).all(userId, sinceTs, untilTs, limit);
}

export function deleteHRVSamples(userId) {
  const result = db.prepare('DELETE FROM hrv_samples WHERE user_id = ?').run(userId);
  db.prepare('UPDATE daily_summary SET hrv_avg = NULL, updated_at = ? WHERE user_id = ?').run(now(), userId);
  return result.changes;
}

// --- breathing_sessions & meditation_sessions ---

export function createBreathingSession({ sessionId, userId, pattern, minutes, completedAt }) {
  db.prepare(`
    INSERT OR REPLACE INTO breathing_sessions (session_id, user_id, pattern, minutes, completed_at)
    VALUES (?, ?, ?, ?, ?)
  `).run(sessionId, userId, pattern, minutes, completedAt || now());
}

export function createMeditationSession({ sessionId, userId, minutes, completedAt }) {
  db.prepare(`
    INSERT OR REPLACE INTO meditation_sessions (session_id, user_id, minutes, completed_at)
    VALUES (?, ?, ?, ?)
  `).run(sessionId, userId, minutes, completedAt || now());
}

export function getBreathingSessions({ userId, sinceTs, untilTs }) {
  return db.prepare(`
    SELECT session_id, pattern, minutes, completed_at
    FROM breathing_sessions
    WHERE user_id = ? AND completed_at >= ? AND completed_at <= ?
    ORDER BY completed_at DESC
  `).all(userId, sinceTs, untilTs);
}

export function getMeditationSessions({ userId, sinceTs, untilTs }) {
  return db.prepare(`
    SELECT session_id, minutes, completed_at
    FROM meditation_sessions
    WHERE user_id = ? AND completed_at >= ? AND completed_at <= ?
    ORDER BY completed_at DESC
  `).all(userId, sinceTs, untilTs);
}

// --- daily_summary ---

export function upsertDailySummary({ userId, date, payload }) {
  const cols = [
    'stress_avg', 'stress_max', 'stress_min', 'stress_high_minutes',
    'hrv_avg', 'breathing_count', 'breathing_minutes',
    'meditation_count', 'meditation_minutes'
  ];
  const setClauses = cols.map(c => `${c} = COALESCE(?, ${c})`).join(', ');
  const insertCols = ['user_id', 'date', ...cols, 'updated_at'].join(', ');
  const insertPlaceholders = ['?', '?', ...cols.map(() => '?'), '?'].join(', ');
  const updateExpr = `${setClauses}, updated_at = ?`;

  const insertVals = [
    userId, date,
    payload.stressAvg ?? null,
    payload.stressMax ?? null,
    payload.stressMin ?? null,
    payload.stressHighMinutes ?? null,
    payload.hrvAvg ?? null,
    payload.breathingCount ?? null,
    payload.breathingMinutes ?? null,
    payload.meditationCount ?? null,
    payload.meditationMinutes ?? null,
    now(),
  ];
  const updateVals = [
    payload.stressAvg ?? null,
    payload.stressMax ?? null,
    payload.stressMin ?? null,
    payload.stressHighMinutes ?? null,
    payload.hrvAvg ?? null,
    payload.breathingCount ?? null,
    payload.breathingMinutes ?? null,
    payload.meditationCount ?? null,
    payload.meditationMinutes ?? null,
    now(),
    userId, date,
  ];

  db.prepare(`
    INSERT INTO daily_summary (${insertCols})
    VALUES (${insertPlaceholders})
    ON CONFLICT(user_id, date) DO UPDATE SET ${updateExpr}
    WHERE daily_summary.user_id = ? AND daily_summary.date = ?
  `).run(...insertVals, ...updateVals);
}

export function getDailySummary({ userId, dateFrom, dateTo }) {
  return db.prepare(`
    SELECT date, stress_avg, stress_max, stress_min, stress_high_minutes,
           hrv_avg, breathing_count, breathing_minutes,
           meditation_count, meditation_minutes, updated_at
    FROM daily_summary
    WHERE user_id = ? AND date >= ? AND date <= ?
    ORDER BY date ASC
  `).all(userId, dateFrom, dateTo);
}

/// Cron job:每日 00:30 跑,基于昨天的 stress_history / hrv / sessions 算 daily_summary.
/// 服务器 UTC 时间;为了适配国内用户(UTC+8),用 (now-8h) 算"昨天"避免边界问题.
export function aggregateYesterdayDailySummary() {
  // 用 UTC+8 算昨天的 0:00-23:59 边界
  const tzOffsetMs = 8 * 3600_000;   // UTC+8 默认(国内用户为主)
  const now = Date.now();
  const localNow = now + tzOffsetMs;
  const localDayStart = Math.floor(localNow / 86400_000) * 86400_000 - 86400_000;  // 昨天 00:00 (UTC+8)
  const yesterdayStartTs = localDayStart - tzOffsetMs;
  const yesterdayEndTs = yesterdayStartTs + 86400_000 - 1;
  const dateStr = new Date(localDayStart).toISOString().slice(0, 10);

  // 找有 stress_history / sessions 的所有 user
  const users = db.prepare(`
    SELECT DISTINCT user_id FROM (
      SELECT user_id FROM stress_history WHERE recorded_at >= ? AND recorded_at <= ?
      UNION SELECT user_id FROM hrv_samples WHERE measured_at >= ? AND measured_at <= ?
      UNION SELECT user_id FROM breathing_sessions WHERE completed_at >= ? AND completed_at <= ?
      UNION SELECT user_id FROM meditation_sessions WHERE completed_at >= ? AND completed_at <= ?
    )
  `).all(
    yesterdayStartTs, yesterdayEndTs,
    yesterdayStartTs, yesterdayEndTs,
    yesterdayStartTs, yesterdayEndTs,
    yesterdayStartTs, yesterdayEndTs
  );

  let count = 0;
  for (const { user_id } of users) {
    const stress = db.prepare(`
      SELECT AVG(score) as avg, MAX(score) as max, MIN(score) as min,
             SUM(CASE WHEN score >= 70 THEN 1 ELSE 0 END) as high_count
      FROM stress_history WHERE user_id = ? AND recorded_at >= ? AND recorded_at <= ?
    `).get(user_id, yesterdayStartTs, yesterdayEndTs);
    const hrv = db.prepare(`
      SELECT AVG(value_ms) as avg FROM hrv_samples
      WHERE user_id = ? AND measured_at >= ? AND measured_at <= ?
    `).get(user_id, yesterdayStartTs, yesterdayEndTs);
    const breath = db.prepare(`
      SELECT COUNT(*) as cnt, SUM(minutes) as min FROM breathing_sessions
      WHERE user_id = ? AND completed_at >= ? AND completed_at <= ?
    `).get(user_id, yesterdayStartTs, yesterdayEndTs);
    const med = db.prepare(`
      SELECT COUNT(*) as cnt, SUM(minutes) as min FROM meditation_sessions
      WHERE user_id = ? AND completed_at >= ? AND completed_at <= ?
    `).get(user_id, yesterdayStartTs, yesterdayEndTs);

    upsertDailySummary({
      userId: user_id,
      date: dateStr,
      payload: {
        stressAvg: stress.avg,
        stressMax: stress.max,
        stressMin: stress.min,
        // 假设每条 history 间隔 5min,powieks * 5 ≈ 高压分钟
        stressHighMinutes: (stress.high_count || 0) * 5,
        hrvAvg: hrv.avg,
        breathingCount: breath.cnt || 0,
        breathingMinutes: breath.min || 0,
        meditationCount: med.cnt || 0,
        meditationMinutes: med.min || 0,
      },
    });
    count++;
  }
  return { date: dateStr, usersAggregated: count };
}

// --- user_share_prefs ---

export function getSharePrefs(userId) {
  let row = db.prepare(`SELECT * FROM user_share_prefs WHERE user_id = ?`).get(userId);
  if (!row) {
    // 懒初始化默认值
    db.prepare(`
      INSERT INTO user_share_prefs (user_id, share_stress, share_training, share_hrv, updated_at)
      VALUES (?, 1, 0, 0, ?)
    `).run(userId, now());
    row = db.prepare(`SELECT * FROM user_share_prefs WHERE user_id = ?`).get(userId);
  }
  return {
    shareStress: !!row.share_stress,
    shareTraining: !!row.share_training,
    shareHRV: !!row.share_hrv,
  };
}

export function updateSharePrefs({ userId, shareStress, shareTraining, shareHRV }) {
  const cur = getSharePrefs(userId);  // 确保有 row
  db.prepare(`
    UPDATE user_share_prefs
    SET share_stress = ?, share_training = ?, share_hrv = ?, updated_at = ?
    WHERE user_id = ?
  `).run(
    shareStress != null ? (shareStress ? 1 : 0) : (cur.shareStress ? 1 : 0),
    shareTraining != null ? (shareTraining ? 1 : 0) : (cur.shareTraining ? 1 : 0),
    shareHRV != null ? (shareHRV ? 1 : 0) : (cur.shareHRV ? 1 : 0),
    now(),
    userId
  );
  return getSharePrefs(userId);
}
