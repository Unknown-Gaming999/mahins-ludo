'use strict';
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();
const db = admin.database();
const OPTS = { region: 'us-central1', maxInstances: 20, memory: '256MiB' };

// ---------- Rules constants ----------
const START = [0, 13, 26, 39];
const SAFE = new Set([0, 8, 13, 21, 26, 34, 39, 47]);
const FINISH = 56;
const TURN_MS = 45000;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// ---------- Helpers ----------
function authUid(req) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  return req.auth.uid;
}
function cleanCode(v) {
  const c = String(v || '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(c)) throw new HttpsError('invalid-argument', 'Room code must be 6 letters or digits.');
  return c;
}
function newCode() {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
  return s;
}
async function getProfile(uid) {
  const v = (await db.ref('users/' + uid).get()).val() || {};
  const name = String(v.name || 'Player').trim().slice(0, 16) || 'Player';
  const avatar = Number.isInteger(v.avatar) ? v.avatar : 0;
  return { name, avatar };
}
function playerObj(prof, now) {
  return { name: prof.name, avatar: prof.avatar, joinedAt: now, connected: true, lastSeen: now };
}
const absIdx = (color, p) => (START[color] + p) % 52;

async function mutate(code, fn) {
  const ref = db.ref('rooms/' + code);
  let existed = false, err = null, out = null;
  await ref.transaction((room) => {
    existed = false; err = null; out = null;
    if (room === null) return null;
    existed = true;
    const ctx = { remove: false };
    try { out = fn(room, Date.now(), ctx); } catch (e) { err = e; return; }
    return ctx.remove ? null : room;
  });
  if (!existed) throw new HttpsError('not-found', 'Room not found.');
  if (err) throw err;
  return out;
}

function needPlaying(room) {
  if (room.status !== 'playing' || !room.game) throw new HttpsError('failed-precondition', 'The game is not running.');
  return room.game;
}
function uidByColor(room, color) {
  for (const [u, p] of Object.entries(room.players || {})) if (p.color === color) return u;
  return null;
}
function activeColors(room) {
  return room.game.order.filter((c) => {
    const u = uidByColor(room, c);
    return u && !room.players[u].left;
  });
}
function passTurn(room, now) {
  const g = room.game;
  const act = activeColors(room);
  if (act.length === 0) return;
  const i = g.order.indexOf(g.turn);
  for (let k = 1; k <= g.order.length; k++) {
    const c = g.order[(i + k) % g.order.length];
    if (act.includes(c)) { g.turn = c; break; }
  }
  g.phase = 'roll';
  delete g.movable;
  g.sixes = 0;
  g.turnDeadline = now + TURN_MS;
  g.seq = (g.seq || 0) + 1;
}
function finishGame(room, winnerColor, now) {
  const g = room.game;
  room.status = 'finished';
  room.finishedAt = now;
  g.phase = 'over';
  delete g.movable;
  if (winnerColor !== null && winnerColor !== undefined) g.winner = winnerColor;
  g.seq = (g.seq || 0) + 1;
  const uids = Object.entries(room.players).filter(([, p]) => p.color !== undefined).map(([u]) => u);
  return { uids, winner: winnerColor === null || winnerColor === undefined ? null : uidByColor(room, winnerColor) };
}
function movableTokens(tokens, dice) {
  const r = [];
  tokens.forEach((p, i) => {
    if (p === -1) { if (dice === 6) r.push(i); }
    else if (p < FINISH && p + dice <= FINISH) r.push(i);
  });
  return r;
}
function beginGame(room, now) {
  const entries = Object.entries(room.players).sort((a, b) => a[1].joinedAt - b[1].joinedAt);
  const n = entries.length;
  const seats = n === 2 ? [0, 2] : n === 3 ? [0, 1, 2] : [0, 1, 2, 3];
  const tokens = {};
  entries.forEach(([, p], i) => { p.color = seats[i]; p.missed = 0; tokens['c' + seats[i]] = [-1, -1, -1, -1]; });
  room.status = 'playing';
  room.startedAt = now;
  delete room.isPublic;
  room.game = { order: seats, tokens, turn: seats[0], phase: 'roll', dice: 0, diceSeq: 0, seq: 0, sixes: 0, turnDeadline: now + TURN_MS };
}
function joinLogic(room, uid, prof, now) {
  const ex = room.players[uid];
  if (ex) {
    if (ex.left) throw new HttpsError('failed-precondition', 'You left this game and cannot rejoin it.');
    return;
  }
  if (room.status !== 'lobby') throw new HttpsError('failed-precondition', 'This game has already started.');
  if (Object.keys(room.players).length >= room.maxPlayers) throw new HttpsError('resource-exhausted', 'This room is full.');
  room.players[uid] = playerObj(prof, now);
  if (room.isPublic && Object.keys(room.players).length === room.maxPlayers) beginGame(room, now);
}
async function recordStats(stats) {
  try {
    for (const u of stats.uids) {
      await db.ref('stats/' + u + '/gamesPlayed').transaction((v) => (v || 0) + 1);
    }
    if (stats.winner) await db.ref('stats/' + stats.winner + '/wins').transaction((v) => (v || 0) + 1);
  } catch (e) { console.error('stats error', e); }
}
async function finalize(out) {
  if (out && out.stats) { await recordStats(out.stats); delete out.stats; }
  return out || { ok: true };
}
async function cleanupOld(now) {
  try {
    const old = await db.ref('rooms').orderByChild('createdAt').endAt(now - 24 * 3600 * 1000).limitToFirst(25).get();
    const updates = {};
    old.forEach((s) => { updates[s.key] = null; });
    if (Object.keys(updates).length) await db.ref('rooms').update(updates);
  } catch (e) { console.error('cleanup error', e); }
}
async function makeRoom(uid, prof, max, isPublic) {
  const now = Date.now();
  await cleanupOld(now);
  for (let t = 0; t < 10; t++) {
    const code = newCode();
    const room = { code, host: uid, status: 'lobby', createdAt: now, maxPlayers: max, players: {} };
    if (isPublic) room.isPublic = true;
    room.players[uid] = playerObj(prof, now);
    const res = await db.ref('rooms/' + code).transaction((cur) => (cur === null ? room : undefined));
    if (res.committed) return { code, status: 'lobby' };
  }
  throw new HttpsError('internal', 'Could not create a room. Please try again.');
}

// ---------- Callable functions ----------
exports.createRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const prof = await getProfile(uid);
  const max = Math.min(4, Math.max(2, parseInt(req.data && req.data.maxPlayers, 10) || 4));
  return makeRoom(uid, prof, max, false);
});

exports.joinRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const prof = await getProfile(uid);
  return mutate(code, (room, now) => {
    joinLogic(room, uid, prof, now);
    return { code, status: room.status };
  });
});

exports.quickMatch = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const prof = await getProfile(uid);
  const now = Date.now();
  const snap = await db.ref('rooms').orderByChild('isPublic').equalTo(true).limitToLast(40).get();
  const cands = [];
  snap.forEach((s) => {
    const r = s.val();
    if (r && r.status === 'lobby' && now - r.createdAt < 15 * 60000 && r.players &&
        (r.players[uid] || Object.keys(r.players).length < r.maxPlayers)) cands.push(s.key);
  });
  for (const code of cands) {
    try {
      return await mutate(code, (room, n) => { joinLogic(room, uid, prof, n); return { code, status: room.status }; });
    } catch (e) { /* room filled or vanished, try next */ }
  }
  return makeRoom(uid, prof, 4, true);
});

exports.startGame = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  return mutate(code, (room, now) => {
    if (room.host !== uid) throw new HttpsError('permission-denied', 'Only the host can start the game.');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', 'The game has already started.');
    if (Object.keys(room.players).length < 2) throw new HttpsError('failed-precondition', 'At least 2 players are needed.');
    beginGame(room, now);
    return { ok: true };
  });
});

exports.rollDice = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    const me = room.players[uid];
    if (!me || me.left || g.turn !== me.color) throw new HttpsError('failed-precondition', 'It is not your turn.');
    if (g.phase !== 'roll') throw new HttpsError('failed-precondition', 'Move a token first.');
    const dice = crypto.randomInt(1, 7);
    me.missed = 0;
    g.dice = dice;
    g.diceSeq = (g.diceSeq || 0) + 1;
    g.rolledBy = me.color;
    g.seq = (g.seq || 0) + 1;
    delete g.event;
    g.sixes = dice === 6 ? (g.sixes || 0) + 1 : 0;
    if (g.sixes >= 3) {
      g.event = me.name + ' rolled three sixes in a row - turn lost!';
      passTurn(room, now);
      return { dice };
    }
    const mv = movableTokens(g.tokens['c' + me.color], dice);
    if (mv.length === 0) {
      g.event = me.name + ' rolled ' + dice + ' - no move possible';
      passTurn(room, now);
      return { dice };
    }
    g.phase = 'move';
    g.movable = mv;
    g.turnDeadline = now + TURN_MS;
    return { dice };
  });
  return finalize(out);
});

exports.moveToken = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const idx = parseInt(req.data && req.data.token, 10);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    const me = room.players[uid];
    if (!me || me.left || g.turn !== me.color) throw new HttpsError('failed-precondition', 'It is not your turn.');
    if (g.phase !== 'move' || !(g.movable || []).includes(idx)) throw new HttpsError('failed-precondition', 'That token cannot move.');
    const toks = g.tokens['c' + me.color];
    const from = toks[idx];
    const to = from === -1 ? 0 : from + g.dice;
    toks[idx] = to;
    me.missed = 0;
    let captured = 0;
    if (to <= 50) {
      const a = absIdx(me.color, to);
      if (!SAFE.has(a)) {
        for (const c of g.order) {
          if (c === me.color) continue;
          const arr = g.tokens['c' + c];
          arr.forEach((p, j) => {
            if (p >= 0 && p <= 50 && absIdx(c, p) === a) { arr[j] = -1; captured++; }
          });
        }
      }
    }
    g.lastMove = { color: me.color, token: idx, from, to, captured };
    g.seq = (g.seq || 0) + 1;
    if (toks.every((p) => p === FINISH)) {
      delete g.event;
      return { ok: true, stats: finishGame(room, me.color, now) };
    }
    const bonus = g.dice === 6 || captured > 0 || to === FINISH;
    if (bonus) {
      g.phase = 'roll';
      delete g.movable;
      g.turnDeadline = now + TURN_MS;
      if (captured > 0) g.event = me.name + ' captured ' + captured + ' token' + (captured > 1 ? 's' : '') + '! Roll again.';
      else if (to === FINISH) g.event = me.name + ' got a token home! Roll again.';
      else g.event = me.name + ' rolled a 6 - roll again!';
    } else {
      delete g.event;
      passTurn(room, now);
    }
    return { ok: true };
  });
  return finalize(out);
});

exports.skipTurn = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    if (!room.players[uid]) throw new HttpsError('permission-denied', 'You are not in this room.');
    const curUid = uidByColor(room, g.turn);
    const cur = curUid && room.players[curUid];
    if (!cur) throw new HttpsError('failed-precondition', 'Nothing to skip.');
    const expired = now > g.turnDeadline;
    const dropped = cur.connected === false && cur.lastSeen && now - cur.lastSeen > 10000;
    if (!expired && !dropped) throw new HttpsError('failed-precondition', 'The turn is still active.');
    let stats = null;
    if (expired && !dropped) {
      cur.missed = (cur.missed || 0) + 1;
      if (cur.missed >= 3) cur.left = true;
    }
    g.event = cur.name + (cur.left ? ' was removed for inactivity' : ' missed a turn');
    const act = activeColors(room);
    if (act.length < 2) stats = finishGame(room, act.length ? act[0] : null, now);
    else passTurn(room, now);
    return { ok: true, stats };
  });
  return finalize(out);
});

exports.leaveRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  let out;
  try {
    out = await mutate(code, (room, now, ctx) => {
      const me = room.players[uid];
      if (!me) return { ok: true };
      if (room.status === 'lobby') {
        delete room.players[uid];
        const rest = Object.entries(room.players);
        if (rest.length === 0) ctx.remove = true;
        else if (room.host === uid) {
          rest.sort((a, b) => a[1].joinedAt - b[1].joinedAt);
          room.host = rest[0][0];
        }
        return { ok: true };
      }
      if (room.status === 'playing') {
        me.left = true;
        me.connected = false;
        const g = room.game;
        const act = activeColors(room);
        if (act.length < 2) return { ok: true, stats: finishGame(room, act.length ? act[0] : null, now) };
        if (g.turn === me.color) passTurn(room, now);
      }
      return { ok: true };
    });
  } catch (e) {
    if (e.code === 'not-found') return { ok: true };
    throw e;
  }
  return finalize(out);
});
