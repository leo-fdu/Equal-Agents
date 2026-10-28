import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { Engine } from './core.mjs';
import { Runtime } from './runtime.mjs';
import { Sources } from './sources.mjs';

const root = process.argv[2]; if (!root) throw Error('Data directory required');
const tokens = new Map();
const send = value => process.stdout.write(JSON.stringify(value) + '\n');
const bridge = { register(tool) { const token = randomBytes(32).toString('hex'); tokens.set(token, tool); return token; }, unregister(token) { tokens.delete(token); }, url: '' };
const web = http.createServer(async (req, res) => {
  const reply = (code, data) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(data)); };
  const tool = tokens.get((req.headers.authorization || '').replace(/^Bearer /, ''));
  if (req.method !== 'POST' || req.url !== '/tool' || !tool || req.headers.origin) return reply(403, { error: 'Forbidden' });
  let body = '';
  try {
    for await (const part of req) { body += part; if (body.length > 100000) throw Error('Request too large'); }
    reply(200, await tool(JSON.parse(body)));
  } catch (e) { reply(400, { error: e.message }); }
});
await new Promise(resolve => web.listen(0, '127.0.0.1', resolve));
bridge.url = `http://127.0.0.1:${web.address().port}/tool`;
const runtime = new Runtime(root, bridge), sources = new Sources();
const engine = new Engine(path.join(root, 'meetings'), args => runtime.run(args), sources, send);
let stopping = false;
async function shutdown() { if (stopping) return; stopping = true; await engine.close(); web.close(); process.exit(0); }
process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown); process.stdin.on('end', shutdown);
async function command(message) {
  const { id, method, params = {} } = message;
  try {
    let result;
    switch (method) {
      case 'list': result = engine.list(params.includeDeleted === true); break;
      case 'delete': result = await engine.delete(params.id); break;
      case 'restore': result = engine.restore(params.id); break;
      case 'create': result = engine.create(params); break;
      case 'start': result = engine.start(params.id); break;
      case 'pause': result = await engine.pause(params.id); break;
      case 'skip': result = engine.skip(params.id, params.turnID); break;
      case 'updateMember': result = engine.updateMember(params.id, params.memberID, params.settings); break;
      case 'catalog': result = await runtime.catalog(params.runtime); break;
      case 'levels': result = await runtime.levels(params); break;
      case 'export': result = engine.export(params.id); break;
      case 'attach': {
        const room = engine.get(params.id);
        if (!room.shared || room.status !== 'draft') throw Error('Add attachments before starting a meeting with shared sources enabled');
        if (typeof params.text !== 'string' || params.text.length > 2_000_000) throw Error('Attachment text must not exceed 2,000,000 characters');
        sources.add(room, 'user', { title: params.title, text: params.text, kind: 'attachment', url: '' }); engine.save(room); result = room; break;
      }
      case 'shutdown': await shutdown(); return;
      default: throw Error('Unknown method');
    }
    send({ id, result });
  } catch (e) { send({ id, error: e.message }); }
}
let buffer = ''; process.stdin.setEncoding('utf8');
process.stdin.on('data', text => {
  buffer += text; if (buffer.length > 15_000_000) { process.stderr.write('Request too large\n'); void shutdown(); return; }
  let i; while ((i = buffer.indexOf('\n')) >= 0) { const line = buffer.slice(0, i); buffer = buffer.slice(i + 1); try { void command(JSON.parse(line)); } catch (e) { send({ error: e.message }); } }
});
send({ type: 'ready' });
