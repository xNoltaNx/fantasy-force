import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

// The SQL can't run here, so these keep its two copies and the functions in step.

const dir = dirname(fileURLToPath(import.meta.url))
const read = (f: string) => readFileSync(join(dir, f), 'utf8').replace(/\r\n/g, '\n')
const section = (sql: string) => sql.slice(sql.indexOf('-- ---------- Discord bot ----------'), sql.indexOf('-- ---------- End of Discord bot ----------'))

describe('the Discord SQL', () => {
  const bot = read('discord-bot.sql')
  const schema = read('schema.sql')

  it('is the same in schema.sql and discord-bot.sql', () => {
    expect(section(bot).length).toBeGreaterThan(1000)
    expect(section(schema)).toBe(section(bot))
  })

  it('has, for every SQL function the Edge Functions call, a definition that only the service key may run', () => {
    const shared = join(dir, 'functions', '_shared')
    const ts = readdirSync(shared).filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts')).map((f) => readFileSync(join(shared, f), 'utf8')).join('\n')
    const called = [...new Set([...ts.matchAll(/rpc(?:<[^>]*>)?\('(\w+)'/g)].map((m) => m[1]!))]
    expect(called.length).toBeGreaterThan(5)
    const grant = /grant execute on function ([\s\S]*?) to service_role;/.exec(section(bot))?.[1] ?? ''
    for (const name of called) {
      expect(section(bot), name).toContain(`create or replace function public.${name}(`)
      expect(grant, name).toContain(`public.${name}(`)
    }
  })
})
