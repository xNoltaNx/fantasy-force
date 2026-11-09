// The FantasyForce addon preview: the addon's real Lua files run unmodified under fengari-web, in the pretend
// game of fakegame.lua (the API, shared with the addon's tests), world.lua (the guild) and preview.lua (input
// in, drawing out). This file draws the game's frames as DOM in a WoW-like style and passes the mouse, keys
// and chat back in. Built into dist/ by build.mjs, which puts the Lua, the TGAs and the font in data.js.
(function () {
  'use strict';
  const D = window.PREVIEW_DATA;
  const F = window.fengari;
  const { lua, lauxlib, lualib, to_luastring } = F;
  const SCREEN_W = 1440, SCREEN_H = 870;
  const game = document.getElementById('game');
  const layer = document.getElementById('frames');
  const tipEl = document.getElementById('tooltip');

  // ---------------------------------------------------------------- fonts --
  // Blizzard's font objects: size and colour. Friz Quadrata isn't free: Marcellus (OFL) stands in for it.
  const FRIZ = '"Marcellus", "Friz Quadrata TT", Georgia, serif';
  const CHATFONT = '"Arial Narrow", Arial, sans-serif';
  const FONTS = {
    GameFontNormal: [12, '#ffd100'], GameFontHighlight: [12, '#ffffff'], GameFontDisable: [12, '#808080'],
    GameFontNormalSmall: [10, '#ffd100'], GameFontHighlightSmall: [10, '#ffffff'], GameFontDisableSmall: [10, '#808080'],
    GameFontNormalLarge: [16, '#ffd100'], GameFontHighlightLarge: [16, '#ffffff'], ChatFontNormal: [14, '#ffffff', true],
    NumberFontNormal: [13, '#ffffff', true],
  };
  const fontOf = (name) => FONTS[name] || FONTS.GameFontNormal;
  const fontCss = (name) => { const f = fontOf(name); return `${f[0]}px ${f[2] ? CHATFONT : FRIZ}`; };
  const lineHeight = (name) => Math.round(fontOf(name)[0] * 1.25);

  // ------------------------------------------------------------- textures --
  // the game's icons, put in data.js by build.mjs (the question mark for one it couldn't get)
  const iconUrl = (name) => D.icons[name] || D.icons.inv_misc_questionmark || null;
  const FILE_IDS = { 134400: 'inv_misc_questionmark', 136240: 'trade_alchemy' };
  const svg = (body, vb = '0 0 32 32') => 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}">${body}</svg>`);
  // the group finder's role icons: tank, healer and damage in a 256 sheet of 67 px cells, as the game lays them out
  const roleCell = (x, y, body) => `<g transform="translate(${x} ${y})"><circle cx="33.5" cy="33.5" r="30" fill="#1b1206" stroke="#c9a14a" stroke-width="3"/>${body}</g>`;
  const ROLES_SVG = svg(
    roleCell(0, 67, '<path d="M33.5 13l16 6v13c0 11-7 18-16 22-9-4-16-11-16-22V19z" fill="#3d6fd6" stroke="#e8edf7" stroke-width="3"/>')
    + roleCell(67, 0, '<path d="M27 14h13v13h13v13H40v13H27V40H14V27h13z" fill="#38c938" stroke="#eaffea" stroke-width="2.5"/>')
    + roleCell(67, 67, '<path d="M46 12l6 6-22 22-4 1 1-4zM20 38l9 9-4 4-3-3-5 5-3-3 5-5-3-3z" fill="#e04a2a" stroke="#ffe2d6" stroke-width="2"/>'),
    '0 0 256 256');
  // A white square frame tinted by the texture's vertex colour (an item's quality border).
  const iconFrame = (vc) => svg(`<rect x="1.5" y="1.5" width="29" height="29" rx="2" fill="none" stroke="${vc ? rgba([vc[0], vc[1], vc[2], 1]) : '#fff'}" stroke-width="2.5"/>`);
  const roundButton = (sign) => svg(`<circle cx="16" cy="16" r="11" fill="#2a2420" stroke="#c9a14a" stroke-width="2"/><path d="M10 16h12${sign === '+' ? 'M16 10v12' : ''}" stroke="#ffd100" stroke-width="3" stroke-linecap="round"/>`);
  // Lookalikes for the few stock textures the addon names (no Blizzard art files).
  const STOCK = {
    'interface\\lfgframe\\ui-lfg-icon-roles': ROLES_SVG,
    'interface\\buttons\\ui-plusbutton-up': roundButton('+'),
    'interface\\buttons\\ui-minusbutton-up': roundButton('-'),
    'interface\\buttons\\buttonhilight-square': svg('<rect x="1" y="1" width="30" height="30" rx="2" fill="#7c8fe0" fill-opacity=".28" stroke="#cdd6ff" stroke-opacity=".6" stroke-width="2"/>'),
    'interface\\buttons\\checkbuttonhilight': svg('<defs><radialGradient id="c"><stop offset=".55" stop-color="#ffd100" stop-opacity="0"/><stop offset="1" stop-color="#ffe680" stop-opacity=".95"/></radialGradient></defs><rect width="32" height="32" rx="3" fill="url(#c)" stroke="#ffe680" stroke-width="2.5"/>'),
    'interface\\targetingframe\\ui-raidtargetingicon_1': svg('<path d="M16 2l4.1 9 9.8 1-7.4 6.6 2.2 9.6L16 23.2 7.3 28.2l2.2-9.6L2.1 12l9.8-1z" fill="#ffd51a" stroke="#6b4a00" stroke-width="1.6" stroke-linejoin="round"/>'),
    'interface\\dialogframe\\ui-dialog-icon-alertnew': svg('<path d="M16 3L30 28H2z" fill="#f2b705" stroke="#3a2600" stroke-width="2" stroke-linejoin="round"/><rect x="14.4" y="11" width="3.2" height="9" rx="1.2" fill="#1a1000"/><circle cx="16" cy="23.6" r="1.9" fill="#1a1000"/>'),
    'interface\\friendsframe\\informationicon': svg('<circle cx="16" cy="16" r="13" fill="#1d2f52" stroke="#d8b23a" stroke-width="2.5"/><circle cx="16" cy="10" r="2.2" fill="#fff"/><rect x="14" y="14" width="4" height="10" rx="1.4" fill="#fff"/>'),
    'interface\\chatframe\\ui-chaticon-chat-up': svg('<circle cx="16" cy="16" r="14" fill="#2a2018" stroke="#8a7650" stroke-width="2"/><path d="M8 10.5h16a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-8l-5 4v-4H8a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z" fill="#f3e3b5" stroke="#5a4a2a" stroke-width="1"/>'),
    'interface\\friendsframe\\statusicon-online': svg('<circle cx="16" cy="16" r="9" fill="#2fd12f" stroke="#0b4a0b" stroke-width="2.5"/>'),
    'interface\\moneyframe\\ui-goldicon': svg('<circle cx="16" cy="16" r="11" fill="#f5c542" stroke="#7a5600" stroke-width="2.5"/>'),
    'interface\\moneyframe\\ui-silvericon': svg('<circle cx="16" cy="16" r="11" fill="#d8d8e0" stroke="#5c5c66" stroke-width="2.5"/>'),
    'interface\\moneyframe\\ui-coppericon': svg('<circle cx="16" cy="16" r="11" fill="#c8733a" stroke="#5e2c0a" stroke-width="2.5"/>'),
    // the gold ring sits in the texture's top-left part, around the 20x20 icon
    'interface\\minimap\\minimap-trackingborder': svg('<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f6e2a0"/><stop offset=".5" stop-color="#b08a3e"/><stop offset="1" stop-color="#5e4718"/></linearGradient></defs><circle cx="16.3" cy="15.4" r="12.6" fill="none" stroke="#120d05" stroke-width="5.5"/><circle cx="16.3" cy="15.4" r="12.6" fill="none" stroke="url(#g)" stroke-width="3.4"/>', '0 0 53 53'),
    'interface\\minimap\\ui-minimap-background': svg('<circle cx="16" cy="16" r="15.5" fill="#0b0b0b"/>'),
    'interface\\minimap\\ui-minimap-zoombutton-highlight': svg('<defs><radialGradient id="h"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".7" stop-color="#fff" stop-opacity=".15"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs><circle cx="16" cy="16" r="16" fill="url(#h)"/>'),
    'interface\\buttons\\ui-scrollbar-knob': svg('<defs><linearGradient id="k" x1="0" x2="1"><stop offset="0" stop-color="#9c8a62"/><stop offset=".5" stop-color="#e7d7a8"/><stop offset="1" stop-color="#7a6a46"/></linearGradient></defs><rect x="9" y="6" width="14" height="20" rx="4" fill="url(#k)" stroke="#1c160b" stroke-width="1.5"/>'),
    'interface\\questframe\\ui-questtitlehighlight': svg('<defs><linearGradient id="q" x1="0" x2="1"><stop offset="0" stop-color="#5a6fbf" stop-opacity="0"/><stop offset=".12" stop-color="#7e93e0" stop-opacity=".45"/><stop offset=".88" stop-color="#7e93e0" stop-opacity=".45"/><stop offset="1" stop-color="#5a6fbf" stop-opacity="0"/></linearGradient></defs><rect width="32" height="32" fill="url(#q)"/>', '0 0 32 32" preserveAspectRatio="none'),
  };
  const CLASS_BY_COORD = {};
  const tgaUrls = {};
  const missing = new Set();
  const norm = (p) => String(p).toLowerCase().replace(/\//g, '\\');

  // A texture path (or file id) as an image URL, or null when the preview has no lookalike for it.
  function textureUrl(tex, tc, vc) {
    if (typeof tex === 'number') return iconUrl(FILE_IDS[tex] || 'inv_misc_questionmark');
    const p = norm(tex);
    if (p === 'interface\\common\\whiteiconframe') return iconFrame(vc);
    if (STOCK[p]) return STOCK[p];
    const media = p.match(/^interface\\addons\\fantasyforce\\media\\([^.]+)/);
    if (media && tgaUrls[media[1]]) return tgaUrls[media[1]];
    const icon = p.match(/^interface\\icons\\(.+?)(\.blp)?$/);
    if (icon) return iconUrl(icon[1]);
    if (p === 'interface\\targetingframe\\ui-classes-circles' && tc) {
      const cls = CLASS_BY_COORD[tc.slice(0, 4).map((v) => (+v).toFixed(3)).join(',')];
      if (cls) return iconUrl('classicon_' + cls.toLowerCase());
    }
    if (!missing.has(p)) { missing.add(p); console.info('addon preview: no lookalike for texture', tex); }
    return null;
  }
  for (const [cls, c] of Object.entries({
    WARRIOR: [0, 0.25, 0, 0.25], MAGE: [0.25, 0.49609375, 0, 0.25], ROGUE: [0.49609375, 0.7421875, 0, 0.25],
    DRUID: [0.7421875, 0.98828125, 0, 0.25], HUNTER: [0, 0.25, 0.25, 0.5], SHAMAN: [0.25, 0.49609375, 0.25, 0.5],
    PRIEST: [0.49609375, 0.7421875, 0.25, 0.5], WARLOCK: [0.7421875, 0.98828125, 0.25, 0.5], PALADIN: [0, 0.25, 0.5, 0.75],
  })) CLASS_BY_COORD[c.map((v) => v.toFixed(3)).join(',')] = cls;

  // Uncompressed TGA (types 2 and 3) to a PNG data URL, honouring the origin bit.
  function decodeTga(b64) {
    const bin = atob(b64), b = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);
    const idLen = b[0], type = b[2], w = b[12] | (b[13] << 8), h = b[14] | (b[15] << 8), bpp = b[16], desc = b[17];
    if (type !== 2 && type !== 3) throw new Error('TGA type ' + type + ' (only uncompressed TGAs are read)');
    const px = bpp / 8, start = 18 + idLen + (b[1] ? (b[5] | (b[6] << 8)) * Math.ceil(b[7] / 8) : 0);
    const topDown = (desc & 0x20) !== 0, rightToLeft = (desc & 0x10) !== 0;
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    const ctx = c.getContext('2d'), img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const s = start + (y * w + x) * px;
        const dy = topDown ? y : h - 1 - y, dx = rightToLeft ? w - 1 - x : x, d = (dy * w + dx) * 4;
        if (type === 3) { img.data[d] = img.data[d + 1] = img.data[d + 2] = b[s]; img.data[d + 3] = 255; continue; }
        img.data[d] = b[s + 2]; img.data[d + 1] = b[s + 1]; img.data[d + 2] = b[s]; img.data[d + 3] = px === 4 ? b[s + 3] : 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    return c.toDataURL();
  }

  // ------------------------------------------------------------------ text --
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  // WoW's text escapes as HTML: |cAARRGGBB colour |r, |H link |h, |T texture |t, |n and \n.
  function markup(text, size) {
    const s = String(text);
    let out = '', depth = 0, i = 0, run = '';
    const flush = () => { if (run) { out += esc(run); run = ''; } };
    while (i < s.length) {
      const ch = s[i];
      if (ch === '|') {
        const n = s[i + 1];
        if (n === '|') { run += '|'; i += 2; continue; }
        if (n === 'c' && /^[0-9a-fA-F]{8}$/.test(s.substr(i + 2, 8))) { flush(); out += `<span style="color:#${s.substr(i + 4, 6)}">`; depth++; i += 10; continue; }
        if (n === 'r') { flush(); if (depth > 0) { out += '</span>'; depth--; } i += 2; continue; }
        if (n === 'H') { const e = s.indexOf('|h', i + 2); if (e > 0) { i = e + 2; continue; } }
        if (n === 'h') { i += 2; continue; }
        if (n === 'n') { flush(); out += '<br>'; i += 2; continue; }
        if (n === 'T') {
          const e = s.indexOf('|t', i + 2);
          if (e > 0) { flush(); out += inlineIcon(s.slice(i + 2, e), size); i = e + 2; continue; }
        }
        if (n === 'A') { const e = s.indexOf('|a', i + 2); if (e > 0) { i = e + 2; continue; } }
      }
      if (ch === '\n') { flush(); out += '<br>'; i++; continue; }
      run += ch; i++;
    }
    flush();
    while (depth-- > 0) out += '</span>';
    return out;
  }
  function inlineIcon(spec, size) {
    const parts = spec.split(':');
    const h = +parts[1] || size, w = +parts[2] || h;
    const url = textureUrl(parts[0]);
    if (!url) return `<span style="display:inline-block;width:${w}px"></span>`;
    return `<img class="inl" src="${url}" style="width:${w}px;height:${h}px">`;
  }
  // The visible text, line by line, with each inline texture as its width.
  function plainLines(text, size) {
    const lines = [{ s: '', extra: 0 }];
    const s = String(text);
    let i = 0;
    while (i < s.length) {
      const ch = s[i], cur = lines[lines.length - 1];
      if (ch === '|') {
        const n = s[i + 1];
        if (n === '|') { cur.s += '|'; i += 2; continue; }
        if (n === 'c' && /^[0-9a-fA-F]{8}$/.test(s.substr(i + 2, 8))) { i += 10; continue; }
        if (n === 'r' || n === 'h') { i += 2; continue; }
        if (n === 'H') { const e = s.indexOf('|h', i + 2); if (e > 0) { i = e + 2; continue; } }
        if (n === 'n') { lines.push({ s: '', extra: 0 }); i += 2; continue; }
        if (n === 'T') {
          const e = s.indexOf('|t', i + 2);
          if (e > 0) { const p = s.slice(i + 2, e).split(':'); cur.extra += (+p[2] || +p[1] || size); i = e + 2; continue; }
        }
      }
      if (ch === '\n') { lines.push({ s: '', extra: 0 }); i++; continue; }
      cur.s += ch; i++;
    }
    return lines;
  }
  const mctx = document.createElement('canvas').getContext('2d');
  const mcache = new Map();
  // Text size as the game would lay it out: width of the widest line, height of all lines (wrapped at wrap).
  function measure(text, font, wrap, spacing) {
    const key = font + '|' + wrap + '|' + spacing + '|' + text;
    const hit = mcache.get(key);
    if (hit) return hit;
    mctx.font = fontCss(font);
    const size = fontOf(font)[0], lh = lineHeight(font) + (spacing || 0);
    let w = 0, count = 0;
    for (const line of plainLines(text, size)) {
      const lw = mctx.measureText(line.s).width + line.extra;
      if (wrap > 0 && lw > wrap) {
        let cur = 0, n = 1;
        for (const word of line.s.split(/(\s+)/)) {
          const ww = mctx.measureText(word).width;
          if (cur > 0 && cur + ww > wrap && word.trim()) { n++; cur = ww; } else cur += ww;
        }
        count += n; w = Math.max(w, wrap);
      } else { count += 1; w = Math.max(w, lw); }
    }
    const res = [Math.ceil(w), count * lh];
    mcache.set(key, res);
    return res;
  }

  // ------------------------------------------------------------------- lua --
  let L = null;
  const errors = [];
  let errorIndex = 0;
  function pushArg(a) {
    if (typeof a === 'number') lua.lua_pushnumber(L, a);
    else if (typeof a === 'boolean') lua.lua_pushboolean(L, a);
    else if (a == null) lua.lua_pushnil(L);
    else lua.lua_pushstring(L, to_luastring(String(a)));
  }
  function call(name, ...args) {
    if (!L) return null;
    lua.lua_getglobal(L, to_luastring('PREVIEW_CALL'));
    pushArg(name);
    args.forEach(pushArg);
    const status = lua.lua_pcall(L, args.length + 1, 1, 0);
    const out = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    if (status !== lua.LUA_OK) { showError(out); return null; }
    return out;
  }
  function act(name, ...args) {
    const s = call(name, ...args);
    if (s) apply(JSON.parse(s));
  }
  function host(name, fn) {
    lua.lua_pushcfunction(L, fn);
    lua.lua_setglobal(L, to_luastring(name));
  }
  const t0 = performance.now();
  function newState() {
    L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    host('HOST_measure', (S) => {
      const r = measure(lua.lua_tojsstring(S, 1), lua.lua_tojsstring(S, 2), lua.lua_tonumber(S, 3) || 0, lua.lua_tonumber(S, 4) || 0);
      lua.lua_pushnumber(S, r[0]); lua.lua_pushnumber(S, r[1]);
      return 2;
    });
    host('HOST_now', (S) => { lua.lua_pushnumber(S, (performance.now() - t0) / 1000); return 1; });
    host('HOST_time', (S) => { lua.lua_pushinteger(S, Math.floor(Date.now() / 1000)); return 1; });
    const setStr = (k, v) => { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setglobal(L, to_luastring(k)); };
    setStr('FAKEGAME_SRC', D.lua.fakegame);
    setStr('WORLD_SRC', D.lua.world);
    lua.lua_newtable(L);
    D.files.forEach((f, i) => { lua.lua_pushstring(L, to_luastring(f)); lua.lua_rawseti(L, -2, i + 1); });
    lua.lua_setglobal(L, to_luastring('ADDON_FILES'));
    lua.lua_newtable(L);
    D.sources.forEach((s, i) => { lua.lua_pushstring(L, to_luastring(s)); lua.lua_rawseti(L, -2, i + 1); });
    lua.lua_setglobal(L, to_luastring('ADDON_SOURCES'));
    if (lauxlib.luaL_loadbuffer(L, to_luastring(D.lua.preview), null, to_luastring('@preview.lua')) !== lua.LUA_OK
      || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      const msg = lua.lua_tojsstring(L, -1);
      L = null;
      showError(msg);
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- drawing --
  const els = new Map(); // id -> { el, node, sig, top, hlFor }
  let hovered = null, pressed = null;
  const px = (v) => Math.round(v * 100) / 100 + 'px';
  const rgba = (c) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${c[3] == null ? 1 : c[3]})`;
  const cssClass = (s) => String(s || '').replace(/[^A-Za-z0-9_-]/g, '');

  function create(n) {
    const el = document.createElement('div');
    if (n.t === 'F') {
      el.className = 'frame';
      el.dataset.id = n.i;
      if (n.k === 'EditBox') {
        const input = document.createElement('input');
        input.type = 'text';
        input.spellcheck = false;
        input.addEventListener('focus', () => act('focus', n.i));
        input.addEventListener('blur', () => act('blur', n.i));
        input.addEventListener('input', () => act('typed', n.i, input.value));
        input.addEventListener('keydown', (e) => {
          if (e.key === 'Enter') { e.preventDefault(); act('key', n.i, 'ENTER'); }
          else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); act('key', n.i, 'ESCAPE'); }
        });
        el.appendChild(input);
        el.input = input;
      }
      wireMouse(el, n.i);
    } else {
      el.className = n.t === 'S' ? 'fs' : 'tex';
    }
    return el;
  }

  function update(e, n) {
    const el = e.el, st = el.style;
    st.left = px(n.x); st.top = px(n.y); st.width = px(n.w); st.height = px(n.h);
    st.zIndex = n.z;
    st.opacity = n.a < 1 ? n.a : '';
    if (n.t === 'F') {
      const cls = ['frame', 'k-' + n.k];
      if (n.tp) n.tp.split(/[,\s]+/).forEach((t) => cls.push('tpl-' + cssClass(t)));
      if (n.nm === 'Minimap') cls.push('minimap');
      if (n.bd) cls.push(/sliderbar/i.test(n.bd) ? 'bd-slider' : /tooltip/i.test(n.bd) ? 'bd-tooltip' : 'bd-dialog');
      for (const f of ['chk', 'sel', 'lock', 'dis']) if (n[f]) cls.push(f);
      if (n.m || n.wh) cls.push('mouse');
      el.className = cls.join(' ');
      let hit = el.querySelector(':scope > .hit');
      if (n.hit) {
        if (!hit) { hit = document.createElement('div'); hit.className = 'hit'; el.appendChild(hit); }
        hit.style.left = n.hit[0] + 'px'; hit.style.right = n.hit[1] + 'px'; hit.style.top = n.hit[2] + 'px'; hit.style.bottom = n.hit[3] + 'px';
      } else if (hit) hit.remove();
      if (el.input) {
        const inp = el.input;
        inp.style.font = fontCss(n.font);
        inp.style.paddingLeft = n.ins ? n.ins[0] + 'px' : '';
        inp.style.paddingRight = n.ins ? n.ins[1] + 'px' : '';
        if (inp.value !== n.txt) inp.value = n.txt;
        // SetFocus in the addon puts the caret in the box, as in the game
        if (n.foc && document.activeElement !== inp) setTimeout(() => { if (inp.isConnected && document.activeElement !== inp) inp.focus(); }, 0);
        if (n.sela && document.activeElement === inp) inp.select();
      }
    } else if (n.t === 'S') {
      const f = fontOf(n.font);
      st.font = fontCss(n.font);
      st.lineHeight = (lineHeight(n.font) + (n.sp || 0)) + 'px';
      st.color = n.c ? rgba(n.c) : f[1];
      const jh = n.jh || 'CENTER', jv = n.jv || 'MIDDLE';
      st.justifyContent = jh === 'LEFT' ? 'flex-start' : jh === 'RIGHT' ? 'flex-end' : 'center';
      st.textAlign = jh === 'LEFT' ? 'left' : jh === 'RIGHT' ? 'right' : 'center';
      st.alignItems = jv === 'TOP' ? 'flex-start' : jv === 'BOTTOM' ? 'flex-end' : 'center';
      st.whiteSpace = n.fw && !n.nw ? 'pre-wrap' : 'pre';
      const html = markup(n.text, f[0]);
      if (e.html !== html) { el.innerHTML = `<span>${html}</span>`; e.html = html; }
    } else {
      const url = n.tex != null ? textureUrl(n.tex, n.tc, n.vc) : null;
      st.backgroundColor = n.col ? rgba(n.col) : '';
      if (url) {
        st.backgroundImage = `url("${url}")`;
        const tc = n.tc;
        const isClass = typeof n.tex === 'string' && /ui-classes-circles/i.test(n.tex);
        if (tc && tc.length >= 4 && !isClass) {
          const bw = n.w / (tc[1] - tc[0]), bh = n.h / (tc[3] - tc[2]);
          st.backgroundSize = `${bw}px ${bh}px`;
          st.backgroundPosition = `${-tc[0] * bw}px ${-tc[2] * bh}px`;
        } else { st.backgroundSize = '100% 100%'; st.backgroundPosition = ''; }
        st.borderRadius = isClass ? '50%' : '';
      } else st.backgroundImage = '';
      st.filter = n.ds ? 'grayscale(1)' : '';
      st.mixBlendMode = n.bl === 'ADD' ? 'plus-lighter' : '';
    }
  }

  function render(nodes) {
    const seen = new Set();
    for (const n of nodes) {
      seen.add(n.i);
      let e = els.get(n.i);
      if (!e) { e = { el: create(n) }; els.set(n.i, e); layer.appendChild(e.el); }
      e.top = n.t === 'F' ? n.top : (els.get(n.p) || {}).top;
      e.owner = n.hl ? n.p : null;
      const sig = JSON.stringify(n);
      if (e.sig !== sig) { update(e, n); e.sig = sig; e.node = n; }
      // an edit box whose script put its text back (the copy boxes) shows the game's text, not what was typed
      else if (e.el.input && e.el.input.value !== n.txt) e.el.input.value = n.txt;
    }
    // delete first: removing a focused box fires blur, which can render again before this loop ends
    for (const [id, e] of [...els]) if (!seen.has(id) && els.get(id) === e) { els.delete(id); if (e.el.isConnected) e.el.remove(); }
    showHighlights();
  }
  // HIGHLIGHT-layer textures show while their frame is under the mouse (or its highlight is locked).
  function showHighlights() {
    for (const e of els.values()) {
      if (e.owner == null) continue;
      const owner = els.get(e.owner);
      const on = e.owner === hovered || (owner && owner.node && owner.node.lock);
      e.el.style.display = on ? '' : 'none';
    }
  }

  function drawTooltip(t) {
    if (!t) { tipEl.style.display = 'none'; return; }
    let html = `<div class="tt-title" style="color:${t.color ? rgba(t.color) : '#fff'}">${markup(t.title, 14)}</div>`;
    for (const l of t.lines) {
      html += `<div class="tt-line${l.wrap ? ' wrap' : ''}" style="color:${rgba([l.r, l.g, l.b, 1])}">${markup(l.text, 12) || '&nbsp;'}</div>`;
    }
    tipEl.innerHTML = html;
    tipEl.style.display = 'block';
    const o = t.owner || [SCREEN_W / 2, SCREEN_H / 2, 0, 0];
    const w = tipEl.offsetWidth, h = tipEl.offsetHeight;
    let x, y;
    if (t.anchor === 'ANCHOR_TOP') { x = o[0] + o[2] / 2 - w / 2; y = o[1] - h - 4; }
    else if (t.anchor === 'ANCHOR_LEFT') { x = o[0] - w; y = o[1] - h; }
    else { x = o[0] + o[2]; y = o[1] - h; }
    x = Math.max(4, Math.min(SCREEN_W - w - 4, x));
    y = Math.max(4, Math.min(SCREEN_H - h - 4, y));
    tipEl.style.left = x + 'px'; tipEl.style.top = y + 'px';
  }

  let updating = false;
  function apply(s) {
    if (s.nodes) render(s.nodes);
    if ('tooltip' in s || s.nodes) drawTooltip(s.tooltip);
    for (const c of s.chat || []) chatLine(c.text, c);
    const nt = s.notices || {};
    if (nt.chatType) setChatType(nt.chatType, nt.chatTarget);
    if (nt.openChat != null) openChat(nt.openChat);
    if (nt.insertLink) insertLink(nt.insertLink);
    if (s.caught != null) {
      const c = document.getElementById('caught');
      c.textContent = s.caught > 0 ? `${s.caught} caught` : '';
    }
    for (const err of s.errors || []) showError(err);
    if (s.update && !updating) { updating = true; requestAnimationFrame(drive); }
    if (!s.update) updating = false;
    if (nt.reload) setTimeout(() => reload({}), 0);
  }

  // ------------------------------------------------------------------ mouse --
  let mouse = { x: 0, y: 0 }, lastDrive = 0;
  const gamePos = (e) => { const r = game.getBoundingClientRect(); return { x: (e.clientX - r.left) * SCREEN_W / r.width, y: (e.clientY - r.top) * SCREEN_H / r.height }; };
  function drive(ts) {
    if (!updating) return;
    const dt = lastDrive ? Math.min(0.1, (ts - lastDrive) / 1000) : 0.016;
    lastDrive = ts;
    act('drive', mouse.x, mouse.y, dt);
    if (updating) requestAnimationFrame(drive); else lastDrive = 0;
  }

  function wireMouse(el, id) {
    el.addEventListener('mouseenter', () => {
      if (pressed && pressed.dragging) return;
      hovered = id; showHighlights(); act('enter', id);
    });
    el.addEventListener('mouseleave', () => {
      if (pressed && pressed.dragging) return;
      if (hovered === id) hovered = null;
      showHighlights(); act('leave', id);
    });
    el.addEventListener('mousedown', (e) => {
      const e2 = els.get(id);
      if (!e2) return;
      if (e2.node.k === 'EditBox') return;
      e.preventDefault();
      if (document.activeElement && document.activeElement.blur && document.activeElement !== document.body) document.activeElement.blur();
      const p = gamePos(e);
      pressed = { id, x: p.x, y: p.y, button: e.button === 2 ? 'RightButton' : 'LeftButton', dragging: false, shift: e.shiftKey };
      el.classList.add('down');
      if (e2.node.k === 'Slider') { pressed.slider = true; slide(id, p); }
    });
    el.addEventListener('wheel', (e) => {
      const e2 = els.get(id);
      if (!e2 || !e2.node.wh) return;
      e.preventDefault(); e.stopPropagation();
      act('wheel', id, e.deltaY < 0 ? 1 : -1);
    }, { passive: false });
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  }
  function slide(id, p) {
    const n = els.get(id).node;
    const thumb = 24;
    act('setSlider', id, (p.y - n.y - thumb / 2) / Math.max(1, n.h - thumb));
  }
  document.addEventListener('mousemove', (e) => {
    const p = gamePos(e);
    mouse = p;
    if (!pressed) return;
    if (pressed.slider) { slide(pressed.id, p); return; }
    const dx = p.x - pressed.x, dy = p.y - pressed.y;
    if (!pressed.dragging && Math.hypot(dx, dy) > 4) {
      const n = els.get(pressed.id) && els.get(pressed.id).node;
      if (n && n.dr) {
        pressed.dragging = true;
        act('dragStart', pressed.id);
        const now = els.get(pressed.id);
        pressed.moving = !!(now && now.node.mv);
        pressed.top = now && now.top;
        drawTooltip(null);
      }
    }
    if (pressed.dragging && pressed.moving) {
      // the window follows the mouse here; the game hears where it ended up on release
      for (const e2 of els.values()) if (e2.top === pressed.top) e2.el.style.transform = `translate(${dx}px, ${dy}px)`;
    }
  });
  document.addEventListener('mouseup', (e) => {
    if (!pressed) return;
    const p = gamePos(e), pr = pressed;
    pressed = null;
    const e2 = els.get(pr.id);
    if (e2) e2.el.classList.remove('down');
    if (pr.slider) return;
    if (pr.dragging) {
      if (pr.moving) {
        for (const x of els.values()) if (x.top === pr.top) x.el.style.transform = '';
        act('dragMove', pr.id, p.x - pr.x, p.y - pr.y);
      }
      act('dragStop', pr.id);
      return;
    }
    const under = document.elementFromPoint(e.clientX, e.clientY);
    const target = under && under.closest('.frame');
    if (target && +target.dataset.id === pr.id) act('click', pr.id, pr.button, pr.shift || e.shiftKey);
  });

  // ------------------------------------------------------------------- chat --
  const chatLog = document.getElementById('chatlog');
  const chatInput = document.getElementById('chatinput');
  const chatLabel = document.getElementById('chatlabel');
  const CHAT_NAMES = { SAY: ['Say:', '#ffffff'], YELL: ['Yell:', '#ff4040'], GUILD: ['Guild:', '#40ff40'], OFFICER: ['Officer:', '#40c040'],
    PARTY: ['Party:', '#aaaaff'], RAID: ['Raid:', '#ff7f00'], WHISPER: ['Tell', '#ff80ff'] };
  let chatType = 'SAY', chatTarget = '';
  const links = new Map();
  function chatLine(text, c) {
    const div = document.createElement('div');
    div.className = 'chatline';
    div.style.color = rgba([c.r == null ? 1 : c.r, c.g == null ? 1 : c.g, c.b == null ? 1 : c.b, 1]);
    div.innerHTML = markup(text, 14);
    chatLog.appendChild(div);
    while (chatLog.children.length > 120) chatLog.firstChild.remove();
    chatLog.scrollTop = chatLog.scrollHeight;
  }
  function setChatType(t, target) {
    chatType = t; chatTarget = target || '';
    const n = CHAT_NAMES[t] || [t + ':', '#fff'];
    chatLabel.textContent = t === 'WHISPER' ? `Tell ${chatTarget}:` : n[0];
    chatLabel.style.color = n[1];
    chatInput.style.color = n[1];
  }
  // an item link in prefilled text shows as [Name], and goes back to the link when sent
  function openChat(text) {
    chatInput.value = String(text).replace(/\|c[0-9a-fA-F]{8}\|H[^|]*\|h(\[[^\]]*\])\|h\|r/g, (link, name) => { links.set(name, link); return name; });
    chatInput.focus();
  }
  function insertLink(link) {
    const name = (link.match(/\|h(\[[^\]]*\])\|h/) || [])[1] || link;
    links.set(name, link);
    chatInput.value += name;
    chatInput.focus();
  }
  chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      let text = chatInput.value.trim();
      chatInput.value = '';
      if (!text) { chatInput.blur(); return; }
      for (const [name, link] of links) text = text.split(name).join(link);
      links.clear();
      act('chat', text, chatType, chatTarget);
    } else if (e.key === 'Escape') { e.preventDefault(); chatInput.value = ''; chatInput.blur(); }
  });

  document.addEventListener('keydown', (e) => {
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'SELECT')) return;
    if (e.key === 'Escape') act('escape');
    else if (e.key === 'Enter') { e.preventDefault(); chatInput.focus(); }
    else if (e.key === '/') { e.preventDefault(); chatInput.value = '/'; chatInput.focus(); }
  });

  // ----------------------------------------------------------------- errors --
  const errBox = document.getElementById('errorbox');
  function showError(msg) {
    errors.push(String(msg));
    errorIndex = errors.length - 1;
    drawError();
    console.error(msg);
  }
  function drawError() {
    if (!errors.length) { errBox.style.display = 'none'; return; }
    errBox.style.display = 'block';
    errBox.querySelector('.err-count').textContent = `${errorIndex + 1} of ${errors.length}`;
    errBox.querySelector('pre').textContent = errors[errorIndex];
  }
  errBox.querySelector('.err-close').addEventListener('click', () => { errors.length = 0; drawError(); });
  errBox.querySelector('.err-prev').addEventListener('click', () => { errorIndex = Math.max(0, errorIndex - 1); drawError(); });
  errBox.querySelector('.err-next').addEventListener('click', () => { errorIndex = Math.min(errors.length - 1, errorIndex + 1); drawError(); });
  window.addEventListener('error', (e) => showError((e.error && e.error.stack) || e.message));

  // ---------------------------------------------------------------- the bar --
  const bar = {
    race: document.getElementById('race'), officer: document.getElementById('officer'),
    blocked: document.getElementById('blocked'), data: document.getElementById('data'),
    slash: document.getElementById('slash'), reset: document.getElementById('reset'),
  };
  const DEFAULTS = { race: 'Orc', officer: false, blocked: false, data: 'full' };
  let settings = { ...DEFAULTS };
  function readHash() {
    const h = new URLSearchParams(location.hash.slice(1));
    const s = { ...DEFAULTS };
    if (h.get('race')) s.race = h.get('race');
    if (h.get('officer')) s.officer = h.get('officer') === '1';
    if (h.get('blocked')) s.blocked = h.get('blocked') === '1';
    if (h.get('data')) s.data = h.get('data');
    return { s, tab: h.get('tab') || 'last' };
  }
  function showSettings() {
    bar.race.value = settings.race; bar.officer.checked = settings.officer;
    bar.blocked.checked = settings.blocked; bar.data.value = settings.data;
  }

  // A new game: a fresh Lua state, the addon loaded again with the SavedVariables kept (a /reload) or none.
  function boot(s, db, charDB, openTab) {
    settings = s;
    showSettings();
    for (const e of els.values()) e.el.remove();
    els.clear();
    hovered = null; pressed = null; updating = false;
    drawTooltip(null);
    if (!newState()) return;
    setChatType('SAY');
    act('start', s.race, s.officer, s.blocked, s.data, db || '', charDB || '', openTab, SCREEN_W, SCREEN_H);
  }
  function reload(change) {
    const saved = L && call('save');
    const keep = saved ? JSON.parse(saved) : { db: '', char: '', open: 'last' };
    chatLine('(Reloading the interface)', { r: 1, g: 1, b: 0 });
    boot({ ...settings, ...change }, keep.db, keep.char, keep.open);
  }
  bar.race.addEventListener('change', () => reload({ race: bar.race.value }));
  bar.officer.addEventListener('change', () => reload({ officer: bar.officer.checked }));
  bar.blocked.addEventListener('change', () => reload({ blocked: bar.blocked.checked }));
  bar.data.addEventListener('change', () => boot({ ...settings, data: bar.data.value }, '', '', 'last'));
  bar.reset.addEventListener('click', () => { chatLog.innerHTML = ''; boot({ ...DEFAULTS }, '', '', 'last'); });
  bar.slash.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    let text = bar.slash.value.trim();
    if (!text) return;
    if (!text.startsWith('/')) text = '/' + text;
    act('chat', text, chatType, chatTarget);
    bar.slash.select();
  });

  setInterval(() => { if (L) act('tick'); }, 100);

  // For checking it from a script: run a command, type in chat, read the state.
  window.FFPreview = {
    slash: (t) => act('chat', t, chatType, chatTarget),
    chat: (t) => act('chat', t, chatType, chatTarget),
    act, settings: () => settings, errors: () => errors.slice(), boot, reload,
    find: (text, partial) => [...els.values()].filter((e) => e.node && e.node.text != null
      && (partial ? String(e.node.text).includes(text) : e.node.text === text)).map((e) => e.el.getBoundingClientRect()),
    frameAt: (id) => els.get(id) && els.get(id).el.getBoundingClientRect(),
    findTex: (part) => [...els.values()].filter((e) => e.node && typeof e.node.tex === 'string' && e.node.tex.toLowerCase().includes(part.toLowerCase()))
      .map((e) => e.el.getBoundingClientRect()),
  };

  // ------------------------------------------------------------------ start --
  (async function start() {
    try {
      for (const [name, b64] of Object.entries(D.tga)) tgaUrls[name.toLowerCase()] = decodeTga(b64);
    } catch (e) { showError('Reading the addon\'s TGA: ' + e.message); }
    // the stand-in font is an @font-face rule in preview.css; text is measured once it has loaded
    try { await document.fonts.load('12px "Marcellus"'); } catch (e) { console.warn('font', e); }
    const { s, tab } = readHash();
    boot(s, '', '', tab);
  })();
})();
