#!/usr/bin/env node

const args = process.argv.slice(2);
const command = args.shift() || 'list';
const baseURL = (process.env.TEMPO_API_BASE || 'https://tempo.tiyicard.cn').replace(/\/$/, '');
const adminToken = process.env.TEMPO_ADMIN_TOKEN || process.env.ADMIN_TOKEN || '';

function usage(exitCode = 0) {
  console.log(`Tempo 漂流瓶审核工具

用法:
  npm run moderate -- list [--status open|resolved|all] [--limit 50] [--json]
  npm run moderate -- hide REPORT_ID [--note "处理说明"]
  npm run moderate -- restore REPORT_ID [--note "处理说明"]
  npm run moderate -- dismiss REPORT_ID [--note "处理说明"]

环境变量:
  TEMPO_ADMIN_TOKEN  必填;不会写入命令输出
  TEMPO_API_BASE     可选;默认 https://tempo.tiyicard.cn`);
  process.exit(exitCode);
}

function takeOption(name, fallback = null) {
  const index = args.indexOf(name);
  if (index < 0) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`${name} 缺少值`);
  }
  args.splice(index, 2);
  return value;
}

function takeFlag(name) {
  const index = args.indexOf(name);
  if (index < 0) return false;
  args.splice(index, 1);
  return true;
}

function compact(value, max = 100) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

function dateText(timestamp) {
  if (!timestamp) return '—';
  return new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: 'Asia/Shanghai',
  }).format(new Date(timestamp));
}

async function request(path, { method = 'GET', body } = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      'X-Tempo-Admin-Token': adminToken,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${payload.error || '请求失败'}`);
  }
  return payload;
}

function printReports(reports, status) {
  console.log(`${status === 'open' ? '待处理' : status === 'resolved' ? '已处理' : '全部'}举报: ${reports.length}`);
  if (reports.length === 0) {
    console.log('当前队列为空。');
    return;
  }
  for (const [index, report] of reports.entries()) {
    const state = report.status === 'resolved'
      ? `RESOLVED/${report.resolution || 'unknown'}`
      : 'OPEN';
    console.log(`\n${index + 1}. [${state}] ${report.reportId}`);
    console.log(`   举报: ${report.reason} · ${dateText(report.createdAt)} · ${report.reporterName}`);
    if (report.bottle) {
      console.log(`   瓶子: ${report.bottle.status || 'missing'} · ${report.bottle.moodTag || '无标签'} · 累计 ${report.bottle.reportCount || 0} 次举报`);
      console.log(`   内容: ${compact(report.bottle.message) || '(内容已删除)'}`);
    } else if (report.reply) {
      console.log(`   回声: ${report.reply.status || 'missing'} · ${report.reply.authorName || 'Tempo 用户'}`);
      console.log(`   内容: ${compact(report.reply.message) || '(内容已删除)'}`);
    }
    if (report.reviewerNote) console.log(`   处理: ${report.reviewerNote}`);
  }
}

async function main() {
  if (command === 'help' || command === '--help' || command === '-h') usage(0);
  if (!adminToken) {
    throw new Error('缺少 TEMPO_ADMIN_TOKEN;请从服务器安全配置中读取后再运行');
  }
  const endpoint = new URL(baseURL);
  const local = ['127.0.0.1', 'localhost', '::1'].includes(endpoint.hostname);
  if (endpoint.protocol !== 'https:' && !local) {
    throw new Error('远程审核接口必须使用 HTTPS');
  }

  if (command === 'list') {
    const status = takeOption('--status', 'open');
    const limitRaw = Number(takeOption('--limit', '50'));
    const json = takeFlag('--json');
    if (!['open', 'resolved', 'all'].includes(status)) throw new Error('--status 仅支持 open/resolved/all');
    if (!Number.isInteger(limitRaw) || limitRaw < 1 || limitRaw > 300) throw new Error('--limit 必须是 1...300');
    if (args.length > 0) throw new Error(`未知参数: ${args.join(' ')}`);
    const payload = await request(`/admin/moderation/reports?status=${status}&limit=${limitRaw}`);
    if (json) console.log(JSON.stringify(payload, null, 2));
    else printReports(payload.reports || [], status);
    return;
  }

  if (['hide', 'restore', 'dismiss'].includes(command)) {
    const reportID = args.shift();
    if (!reportID) throw new Error(`${command} 缺少 REPORT_ID`);
    const note = takeOption('--note', '');
    if (args.length > 0) throw new Error(`未知参数: ${args.join(' ')}`);
    const payload = await request(`/admin/moderation/reports/${encodeURIComponent(reportID)}/resolve`, {
      method: 'POST',
      body: { action: command, note },
    });
    console.log(`处理完成: ${payload.report.reportId} → ${payload.report.resolution}`);
    if (payload.report.bottle) console.log(`瓶子状态: ${payload.report.bottle.status}`);
    if (payload.report.reply) console.log(`回声状态: ${payload.report.reply.status}`);
    return;
  }

  throw new Error(`未知命令: ${command}`);
}

main().catch(error => {
  console.error(`审核工具错误: ${error.message}`);
  process.exit(1);
});
