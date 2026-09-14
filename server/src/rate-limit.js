// 轻量内存型 rate limiter — 单 server 进程足够,不引外部依赖。
// 多 server 横扩时需换 Redis,但当前架构是单台 Singapore VM,够用。
//
// 用法:
//   app.use('/v1/auth/apple',          rateLimit({ windowMs: 60_000, max: 10, by: 'ip' }));
//   app.use('/v1/friend-requests/*',   rateLimit({ windowMs: 60_000, max: 20, by: 'user' }));
//
// 'ip' = 用 X-Forwarded-For(nginx 在前面);'user' = 用 c.get('userId')(必须排在 requireSession 之后)

const buckets = new Map();   // key → { count, resetAt }

// 每 5min 清一次过期 bucket,避免长期攻击留无限 entries
setInterval(() => {
  const now = Date.now();
  for (const [k, b] of buckets) {
    if (b.resetAt < now) buckets.delete(k);
  }
}, 5 * 60_000).unref();

export function rateLimit({ windowMs, max, by = 'ip', name = 'default' }) {
  return async function rateLimitMiddleware(c, next) {
    let id;
    if (by === 'user') {
      id = c.get('userId') || c.req.header('x-forwarded-for') || 'anon';
    } else {
      id = c.req.header('x-forwarded-for') || 'unknown';
    }
    const key = `${name}:${id}`;
    const now = Date.now();
    const bucket = buckets.get(key);

    if (!bucket || bucket.resetAt < now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
    } else {
      bucket.count += 1;
      if (bucket.count > max) {
        const retryAfter = Math.ceil((bucket.resetAt - now) / 1000);
        c.header('Retry-After', String(retryAfter));
        return c.json(
          { error: '请求过于频繁,请稍后再试', retryAfterSec: retryAfter },
          429
        );
      }
    }

    await next();
  };
}
