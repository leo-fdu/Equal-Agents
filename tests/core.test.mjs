import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Engine } from '../engine/core.mjs';
import { Sources, publicAddress } from '../engine/sources.mjs';

const member = name => ({ name, runtime: 'codex', model: 'test-model', provider: 'OpenAI', persona: name === 'A' ? 'Be practical' : '' });
const config = { topic: 'Test a decision', host: member('Host'), members: [member('A'), member('B')], rounds: 2, shared: true };
const context = p => JSON.parse(p.split('\n\n').slice(1).join('\n\n'));
function fixture(t, run, source = new Sources()) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'equal-agents-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return new Engine(root, run, source);
}
async function finish(engine, room) { engine.start(room.id); await engine.active.get(room.id).done; }

test('host separation, true parallel proposals, exact turns, sequential full history', async t => {
  let proposalCount = 0, release;
  const barrier = new Promise(r => { release = r; }); const seen = [];
  const engine = fixture(t, async args => {
    const c = context(args.prompt); seen.push(c);
    assert.equal(args.toolsAllowed, ['proposal', 'discussion'].includes(c.stage));
    if (c.stage === 'proposal') { proposalCount++; if (proposalCount === 2) release(); await barrier; assert.equal(c.history.length, 1); }
    return `${c.you.name}:${c.stage}:${c.round}`;
  });
  const room = engine.create(config); await finish(engine, room);
  assert.equal(room.status, 'completed'); assert.equal(room.turns.length, 10);
  assert.deepEqual(seen.filter(c => c.you.name === 'Host').map(c => c.stage), ['opening', 'report']);
  for (const c of seen.filter(c => ['discussion', 'final', 'report'].includes(c.stage))) {
    const actual = room.turns.findIndex(t => t.phase === c.stage && t.round === c.round && t.memberID === c.you.id);
    assert.equal(c.history.length, actual);
  }
});

test('failed participant pauses barrier and retry never repeats completed proposal', async t => {
  const calls = new Map(); let fail = true;
  const engine = fixture(t, async args => {
    const c = context(args.prompt), key = c.you.name + c.stage;
    calls.set(key, (calls.get(key) || 0) + 1);
    if (c.stage === 'proposal' && c.you.name === 'B' && fail) throw Error('fixture failure');
    return 'ok';
  });
  const room = engine.create(config); await finish(engine, room);
  assert.equal(room.status, 'paused'); assert.ok(room.turns.filter(t => t.phase === 'discussion').every(t => t.status === 'pending'));
  fail = false; await finish(engine, room);
  assert.equal(room.status, 'completed'); assert.equal(calls.get('Aproposal'), 1); assert.equal(calls.get('Bproposal'), 2);
});

test('pause cancels concurrent proposals; restart retains completed opening', async t => {
  let started; const ready = new Promise(r => { started = r; });
  const engine = fixture(t, async args => {
    const c = context(args.prompt);
    if (c.stage === 'proposal') { started(); await new Promise((_, reject) => args.signal.addEventListener('abort', () => reject(Error('cancelled')), { once: true })); }
    return 'opening';
  });
  const room = engine.create(config); engine.start(room.id); await ready; await engine.pause(room.id);
  assert.equal(room.status, 'paused'); assert.equal(room.turns[0].status, 'completed');
  assert.ok(room.turns.filter(t => t.phase === 'proposal').every(t => t.status === 'interrupted'));
  const restored = new Engine(engine.root, async () => 'restored', new Sources());
  await finish(restored, restored.get(room.id)); assert.equal(restored.get(room.id).turns[0].attempts, 1);
});

test('explicit skip is represented in subsequent context and report', async t => {
  let fail = true; const seen = [];
  const engine = fixture(t, async args => { const c = context(args.prompt); seen.push(c); if (c.stage === 'proposal' && c.you.name === 'A' && fail) throw Error('no access'); return 'ok'; });
  const room = engine.create(config); await finish(engine, room);
  const turn = room.turns.find(t => t.status === 'failed'); engine.skip(room.id, turn.id); fail = false;
  await finish(engine, room);
  assert.ok(seen.at(-1).history.some(h => h.status === 'skipped'));
  assert.throws(() => engine.skip(room.id, room.turns[0].id));
});

test('proposal source visibility, automatic complete search archive, reading receipts', async t => {
  const sources = new Sources(); sources.search = async () => [{ title: 'One', url: 'https://example.com/1', text: 'first', kind: 'search_result' }, { title: 'Two', url: 'https://example.com/2', text: 'second', kind: 'search_result' }];
  const engine = fixture(t, async () => 'ok', sources), room = engine.create(config);
  const a = room.turns[1], b = room.turns[2], state = { localSources: [] };
  await sources.tool(engine, room, a, { action: 'search', query: 'x' }, state, new AbortController().signal);
  assert.equal(room.sources.length, 2); assert.equal(engine.visibleSources(room, a).length, 2); assert.equal(engine.visibleSources(room, b).length, 0);
  await assert.rejects(sources.tool(engine, room, b, { action: 'read_source', id: room.sources[0].id }, state, new AbortController().signal));
  await sources.tool(engine, room, room.turns[3], { action: 'read_source', id: room.sources[0].id }, state, new AbortController().signal);
  assert.equal(room.reads.length, 1); assert.equal(room.reads[0].end, 5);
});

test('sharing off never persists retrieved material into room', async t => {
  const sources = new Sources(); sources.search = async () => [{ title: 'One', url: 'https://example.com', text: 'private' }];
  const engine = fixture(t, async () => 'ok', sources), room = engine.create({ ...config, shared: false });
  const state = { localSources: [] };
  await sources.tool(engine, room, room.turns[1], { action: 'search', query: 'x' }, state, new AbortController().signal);
  assert.equal(room.sources.length, 0); assert.equal(state.localSources.length, 1);
});

test('complete history is retained beyond recent-message window; overflow fails instead of truncating', t => {
  const engine = fixture(t, async () => 'ok'), room = engine.create({ ...config, rounds: 12 });
  for (const turn of room.turns.slice(0, -1)) { turn.status = 'completed'; turn.text = 'Original ' + turn.id; }
  const prompt = engine.prompt(room, room.turns.at(-1));
  assert.equal(context(prompt).history.length, room.turns.length - 1);
  room.maxContextChars = 100; assert.throws(() => engine.prompt(room, room.turns.at(-1)), /Full history/);
});

test('recovery marks running turns interrupted without replay', t => {
  const engine = fixture(t, async () => 'ok'), room = engine.create(config);
  room.status = 'running'; room.turns[0].status = 'running'; engine.save(room);
  const restarted = new Engine(engine.root, async () => { throw Error('must not run'); }, new Sources());
  assert.equal(restarted.get(room.id).status, 'paused'); assert.equal(restarted.get(room.id).turns[0].status, 'interrupted'); assert.equal(restarted.active.size, 0);
});

test('public fetch rejects private, metadata, mapped IPv6, and documentation addresses', () => {
  for (const ip of ['127.0.0.1', '10.0.0.1', '169.254.169.254', '192.168.2.3', '172.16.0.1', '::1', '::ffff:127.0.0.1', 'fc00::1', '2001:db8::1']) assert.equal(publicAddress(ip), false, ip);
  for (const ip of ['1.1.1.1', '8.8.8.8', '2606:4700:4700::1111']) assert.equal(publicAddress(ip), true, ip);
});

test('invalid configurations fail before any model invocation', t => {
  const engine = fixture(t, async () => { throw Error('not expected'); });
  for (const override of [{ topic: '' }, { members: [] }, { rounds: 0 }, { rounds: 1.5 }, { host: { runtime: 'fake', model: 'x' } }]) assert.throws(() => engine.create({ ...config, ...override }));
});

test('no-limit settings persist and unlimited turns remain explicitly cancellable', async t => {
  let entered; const began = new Promise(r => { entered = r; });
  const engine = fixture(t, async args => {
    assert.equal(context(args.prompt).suggestedResponseCharacters, null);
    entered(); await new Promise((_, reject) => args.signal.addEventListener('abort', () => reject(Error('cancelled')), { once: true }));
  });
  const room = engine.create({ ...config, turnSeconds: null, responseLength: null });
  assert.equal(room.turnSeconds, null); assert.equal(room.responseLength, null);
  engine.start(room.id); await began; await engine.pause(room.id);
  assert.equal(room.turns[0].status, 'interrupted');
  const restored = new Engine(engine.root, async () => 'ok', new Sources());
  assert.equal(restored.get(room.id).turnSeconds, null); assert.equal(restored.get(room.id).responseLength, null);
});

test('changing a paused model preserves completed statement provenance', async t => {
  const engine = fixture(t, async args => {
    const c = context(args.prompt); if (c.stage === 'proposal') throw Error('access denied'); return 'original';
  });
  const room = engine.create(config); await finish(engine, room);
  engine.updateMember(room.id, room.host.id, { ...member('Changed name'), model: 'new-model' });
  assert.equal(room.host.model, 'new-model'); assert.equal(room.host.name, 'Host');
  assert.equal(room.turns[0].memberSnapshot.model, 'test-model');
});

test('delete hides a discussion, preserves its evidence across restart, and restore never runs it', async t => {
  const engine = fixture(t, async () => 'recorded statement'), room = engine.create(config);
  engine.sources.add(room, 'user', { title: 'Evidence', text: 'Keep this evidence', kind: 'attachment' });
  await finish(engine, room); const transcript = engine.export(room.id);
  await engine.delete(room.id);
  assert.equal(engine.list().length, 0); assert.equal(engine.list(true).length, 1);
  assert.throws(() => engine.start(room.id), /Restore/);
  const restored = new Engine(engine.root, async () => { throw Error('must not run'); }, new Sources());
  assert.equal(restored.list().length, 0); restored.restore(room.id);
  assert.equal(restored.list().length, 1); assert.equal(restored.get(room.id).status, 'completed');
  assert.equal(restored.export(room.id), transcript); assert.equal(restored.get(room.id).sources[0].text, 'Keep this evidence');
});

test('deleting a running discussion cancels all proposals before restore', async t => {
  let entered; const started = new Promise(r => { entered = r; });
  const engine = fixture(t, async args => {
    if (context(args.prompt).stage === 'proposal') {
      entered(); await new Promise((_, reject) => args.signal.addEventListener('abort', () => reject(Error('cancelled')), { once: true }));
    }
    return 'opening';
  });
  const room = engine.create(config); engine.start(room.id); await started;
  const deletion = engine.delete(room.id);
  assert.throws(() => engine.start(room.id), /Restore/);
  assert.throws(() => engine.restore(room.id), /stop/);
  await deletion;
  assert.equal(engine.active.size, 0); assert.equal(room.status, 'paused'); assert.equal(engine.list().length, 0);
  engine.restore(room.id); assert.equal(room.turns[0].status, 'completed');
  assert.ok(room.turns.filter(t => t.phase === 'proposal').every(t => t.status === 'interrupted'));
});

test('private personas never enter peer or host context in any stage', async t => {
  const engine = fixture(t, async args => {
    const c = context(args.prompt);
    assert.ok(c.participants.every(p => !('persona' in p)));
    for (const name of ['A', 'B']) {
      assert.equal(args.prompt.includes(`PRIVATE_${name}_ROLE`), c.you.name === name);
    }
    return 'Public position without private instructions';
  });
  const room = engine.create({ ...config, members: ['A', 'B'].map(name => ({ ...member(name), persona: `PRIVATE_${name}_ROLE` })) });
  await finish(engine, room); assert.equal(room.status, 'completed');
});

test('initial files and links persist and reach every stage with shared sources off', async t => {
  const materials = [{ kind: 'file', title: 'Brief.txt', text: 'Full initial evidence' }, { kind: 'link', title: 'Reference', text: 'https://example.com' }];
  const engine = fixture(t, async args => { assert.deepEqual(context(args.prompt).topicMaterials, materials); return 'ok'; });
  const room = engine.create({ ...config, shared: false, materials });
  const restored = new Engine(engine.root, engine.run, new Sources());
  await finish(restored, restored.get(room.id));
  assert.equal(restored.get(room.id).status, 'completed');
  assert.ok(restored.export(room.id).includes('Full initial evidence'));
  assert.throws(() => engine.create({ ...config, materials: [{ kind: 'file', title: 'large', text: 'x'.repeat(100001) }] }));
  assert.throws(() => engine.create({ ...config, materials: [{ kind: 'link', title: 'bad', text: 'file:///private' }] }));
});
