// Kill on sight, end to end: the addon's Lua (in .toc order) runs on two pretend game clients from fakegame.lua,
// joined by the guild addon channel, under fengari (Lua 5.3 in JavaScript; the game's is 5.1, so the Lua it runs
// keeps to what both understand). The checks themselves are in kos.test.lua; a failed assert fails this test.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
// @ts-expect-error fengari ships no types
import { lua, lauxlib, lualib, to_luastring } from 'fengari';

const here = dirname(fileURLToPath(import.meta.url));
const addon = join(here, '..', '..', 'addon', 'FantasyForce');
const read = (p: string) => readFileSync(p, 'utf8');

function runLua(testFile: string): string | null {
  const files = read(join(addon, 'FantasyForce.toc')).split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#') && /\.lua$/i.test(l));
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const setStr = (k: string, v: string) => { lua.lua_pushstring(L, to_luastring(v)); lua.lua_setglobal(L, to_luastring(k)); };
  setStr('FAKEGAME_SRC', read(join(here, 'fakegame.lua')));
  lua.lua_newtable(L);
  files.forEach((f, i) => { lua.lua_pushstring(L, to_luastring(f)); lua.lua_rawseti(L, -2, i + 1); });
  lua.lua_setglobal(L, to_luastring('ADDON_FILES'));
  lua.lua_newtable(L);
  files.forEach((f, i) => { lua.lua_pushstring(L, to_luastring(read(join(addon, f)))); lua.lua_rawseti(L, -2, i + 1); });
  lua.lua_setglobal(L, to_luastring('ADDON_SOURCES'));
  const src = to_luastring(read(join(here, testFile)));
  if (lauxlib.luaL_loadbuffer(L, src, null, to_luastring('@' + testFile)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    return lua.lua_tojsstring(L, -1);
  }
  return null;
}

describe('kill on sight', () => {
  it('marks, shares, shows, offers attackers and clears', () => {
    expect(runLua('kos.test.lua')).toBeNull();
  });
});
