import https from 'node:https';
import http from 'node:http';
import dns from 'node:dns/promises';
import { randomUUID, createHash } from 'node:crypto';

export function publicAddress(ip) {
  if (ip.includes(':')) return /^[23][0-9a-f]{3}:/i.test(ip) && !/^2001:(?:0:|db8:)/i.test(ip);
  const n = ip.split('.').map(Number);
  return n.length === 4 && n.every(x => Number.isInteger(x) && x >= 0 && x <= 255) && ![0, 10, 127].includes(n[0]) && n[0] < 224 &&
    !(n[0] === 169 && n[1] === 254) && !(n[0] === 172 && n[1] >= 16 && n[1] <= 31) && !(n[0] === 192 && (n[1] === 168 || n[1] === 0 || n[1] === 2)) && !(n[0] === 100 && n[1] >= 64 && n[1] <= 127) && !(n[0] === 198 && [18, 19, 51].includes(n[1])) && !(n[0] === 203 && n[1] === 0);
}
export async function download(raw, signal, redirects = 0) {
  const url = new URL(raw);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || (url.port && !['80', '443'].includes(url.port))) throw Error('Only public HTTP(S) URLs without credentials are allowed');
  if (redirects > 4) throw Error('Too many redirects');
  const addresses = await dns.lookup(url.hostname.replace(/^\[|\]$/g, ''), { all: true });
  if (!addresses.length || addresses.some(a => !publicAddress(a.address))) throw Error('Local and private network access is not allowed');
  const address = addresses[0];
  return new Promise((resolve, reject) => {
    const req = (url.protocol === 'https:' ? https : http).get(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; EqualAgents/0.1)', Accept: 'text/html,application/rss+xml,text/plain,application/json' },
      signal: AbortSignal.any([signal || new AbortController().signal, AbortSignal.timeout(20000)]),
      // Pin validated DNS results to prevent a second resolution from reaching private hosts.
      lookup: (_hostname, options, cb) => options.all ? cb(null, [address]) : cb(null, address.address, address.family)
    }, response => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        response.resume(); if (!response.headers.location) return reject(Error('Invalid redirect'));
        download(new URL(response.headers.location, url).href, signal, redirects + 1).then(resolve, reject); return;
      }
      if (response.statusCode !== 200) { response.resume(); reject(Error(`Page request failed: HTTP ${response.statusCode}`)); return; }
      let size = 0; const chunks = [];
      response.on('data', x => { size += x.length; if (size > 3_000_000) response.destroy(Error('Page exceeds the 3 MB fetch limit')); else chunks.push(x); });
      response.on('error', reject);
      response.on('end', () => resolve({ body: Buffer.concat(chunks), url: url.href, type: response.headers['content-type'] || '' }));
    }); req.on('error', reject);
  });
}
export function plain(html) {
  return html.replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi, '').replace(/<\/?(?:p|div|h[1-6]|li|br|tr)\b[^>]*>/gi, '\n').replace(/<[^>]+>/g, '')
    .replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (_, n) => { const v = n[0].toLowerCase() === 'x' ? parseInt(n.slice(1), 16) : Number(n); return v <= 0x10ffff ? String.fromCodePoint(v) : ''; })
    .replace(/&(?:amp|lt|gt|quot|apos|nbsp);/g, x => ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&nbsp;': ' ' })[x]).replace(/[ \t]+/g, ' ').replace(/\n\s*\n/g, '\n\n').trim();
}
export class Sources {
  constructor(fetcher = download) { this.fetcher = fetcher; }
  add(room, owner, data, localSources = []) {
    const collection = room.shared ? room.sources : localSources;
    const hash = createHash('sha256').update(data.text || '').digest('hex');
    let item = collection.find(s => s.url === data.url && s.hash === hash);
    if (item) { if (!item.ownerIDs.includes(owner)) item.ownerIDs.push(owner); return item; }
    if (collection.reduce((n, s) => n + s.text.length, 0) + (data.text || '').length > 12_000_000 || collection.length >= 1000) throw Error('Source storage limit reached; unarchived material was not returned');
    item = { id: 'S-' + randomUUID().slice(0, 8), title: String(data.title || data.url || 'Sources').slice(0, 500), url: data.url || '', text: data.text || '', kind: data.kind || 'page',
      query: data.query || '', ownerIDs: [owner], hash, characters: (data.text || '').length, createdAt: new Date().toISOString() };
    collection.push(item); return item;
  }
  async search(query, signal) {
    if (!query?.trim() || query.length > 500) throw Error('Enter a search query of 1–500 characters');
    const response = await this.fetcher('https://www.bing.com/search?format=rss&q=' + encodeURIComponent(query), signal);
    const xml = response.body.toString('utf8');
    const items = [...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)].map(match => {
      const tag = name => plain((match[1].match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)<\\/${name}>`, 'i')) || [])[1] || '');
      return { title: tag('title'), url: tag('link'), text: tag('description'), kind: 'search_result', query };
    }).filter(x => /^https?:\/\//.test(x.url));
    if (!items.length && !/<rss/i.test(xml)) throw Error('Search returned no usable response and may require verification. Use fetch with a known public URL; no results will be invented.');
    return items;
  }
  async tool(engine, room, turn, args, state, signal) {
    const visible = () => room.shared ? engine.visibleSources(room, turn) : state.localSources;
    const offset = Math.max(0, Number.isInteger(args.offset) ? args.offset : 0);
    if (args.action === 'sources') return { shared: room.shared, sources: visible().map(({ text, ...s }) => s) };
    if (args.action === 'search') {
      const results = await this.search(args.query, signal); signal.throwIfAborted();
      const archived = results.map(s => this.add(room, turn.memberID, s, state.localSources));
      return { provider: 'Bing public RSS', coverage: 'Search snippets only, not full pages. Fetch relevant URLs before relying on them.', results: archived };
    }
    if (args.action === 'fetch') {
      const result = await this.fetcher(args.url, signal); signal.throwIfAborted();
      if (result.body.subarray(0, 4).toString() === '%PDF') throw Error('This URL is a PDF. Ask the user to import it into shared sources so the app can extract its text.');
      if (!/text|json|xml|html/.test(result.type)) throw Error('This URL is not a supported text page');
      const html = result.body.toString('utf8');
      const text = /html/.test(result.type) ? plain(html) : html;
      const title = plain((html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1] || result.url);
      const item = this.add(room, turn.memberID, { title, url: result.url, text }, state.localSources);
      return this.read(room, turn, item, offset);
    }
    if (args.action === 'read_source') {
      const item = visible().find(s => s.id === args.id); if (!item) throw Error('Source not found or not visible in this stage');
      return this.read(room, turn, item, offset);
    }
    throw Error('Unknown source action');
  }
  read(room, turn, item, offset) {
    const text = item.text.slice(offset, offset + 14000);
    if (room.shared) room.reads.push({ memberID: turn.memberID, sourceID: item.id, turnID: turn.id, offset, end: offset + text.length, at: new Date().toISOString() });
    return { id: item.id, title: item.title, url: item.url, kind: item.kind, text, offset, totalCharacters: item.text.length, nextOffset: offset + text.length < item.text.length ? offset + text.length : null, note: 'This records delivered passages, not proof of understanding or full reading.' };
  }
}
