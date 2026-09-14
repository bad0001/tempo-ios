// Sign in with Apple identity token 验证.
// Apple 给 client 返回 identityToken (JWT, RS256, Apple 公钥签名).
// Server 用 Apple's JWKS 验证签名 + audience + issuer + 过期.
// 验过后取 sub(Apple 永久用户 ID)+ email(可空)作为账号身份.

import { jwtVerify, createRemoteJWKSet } from 'jose';
import { createHash, randomUUID } from 'node:crypto';
import { upsertUser } from './db.js';

const APPLE_ISS = 'https://appleid.apple.com';
const JWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

const AUDIENCE = process.env.APPLE_BUNDLE_ID || 'com.ayipocket.tempo';

export async function verifyAppleToken(idToken) {
  const { payload } = await jwtVerify(idToken, JWKS, {
    issuer: APPLE_ISS,
    audience: AUDIENCE,
  });
  return payload;
}

export function hashEmail(email) {
  if (!email) return null;
  return createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
}

/// client 提交 identityToken → 我们验签 → 创建/更新 user → 返回 user.
export async function authenticateApple({ idToken, displayName }) {
  const payload = await verifyAppleToken(idToken);
  const appleSub = payload.sub;
  const email = payload.email;
  const emailHash = hashEmail(email);
  const userId = randomUUID();
  const user = upsertUser({ userId, appleSub, emailHash, displayName });
  return user;
}

/// 简化的 Bearer token = user_id(单纯 PoC,生产上应签 JWT 自家).
/// 但因为身份完全由 Apple sub 锚定,且每次请求会带 Apple identityToken 或刷新后的 access token,
/// 这里我们用一个简单的 opaque session token,签名后带 user_id + iat,
/// 用 secret 防伪.
import { SignJWT, jwtVerify as joseVerify } from 'jose';

const SESSION_SECRET = new TextEncoder().encode(
  process.env.SESSION_SECRET || 'tempo-dev-secret-change-me-in-prod-please'
);

export async function issueSessionToken(userId) {
  return await new SignJWT({ uid: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(SESSION_SECRET);
}

export async function verifySessionToken(token) {
  const { payload } = await joseVerify(token, SESSION_SECRET);
  return payload.uid;
}
