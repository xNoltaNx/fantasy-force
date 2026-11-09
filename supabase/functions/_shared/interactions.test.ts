import { describe, expect, it } from 'vitest'
import { handleInteraction, type InteractionDeps } from './interactions.ts'
import { customId } from './message.ts'
import type { Db } from './rest.ts'
import { testSigner } from './testSigner.ts'

const ID = '0b6f8e2c-1d3a-4c5b-9e7f-112233445566'
const SITE = 'https://xnoltanx.github.io/fantasy-force/'

async function setup(answer: unknown = { result: 'in', title: 'Molten Core', role: 'healer' }) {
  const signer = await testSigner()
  const calls: { name: string; args: Record<string, unknown> }[] = []
  const db: Db = { rpc: async <T,>(name: string, args: Record<string, unknown>) => { calls.push({ name, args }); return answer as T } }
  const deps: InteractionDeps = { publicKey: signer.publicKey, applicationId: 'app1', db, siteUrl: SITE, log: () => {} }
  const send = async (payload: unknown, sign = true) => {
    const body = JSON.stringify(payload)
    const ts = '1762560000'
    const headers: Record<string, string> = { 'X-Signature-Timestamp': ts, 'X-Signature-Ed25519': sign ? await signer.sign(ts, body) : '00'.repeat(64) }
    return handleInteraction(deps, new Request('https://x/functions/v1/discord-interactions', { method: 'POST', headers, body }))
  }
  return { send, calls }
}

const press = (choice: string, user = '1234') => ({
  type: 3, application_id: 'app1', data: { custom_id: customId(ID, choice as 'tank'), component_type: 2 }, member: { user: { id: user } },
})

describe('handleInteraction', () => {
  it('answers a signed PING with PONG', async () => {
    const { send } = await setup()
    const res = await send({ type: 1, application_id: 'app1' })
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ type: 1 })
  })

  it('refuses a bad signature with 401', async () => {
    const { send, calls } = await setup()
    expect((await send({ type: 1 }, false)).status).toBe(401)
    expect((await send(press('tank'), false)).status).toBe(401)
    expect(calls).toEqual([])
  })

  it('signs the presser up and answers only them', async () => {
    const { send, calls } = await setup()
    const res = await send(press('healer', '987'))
    expect(calls).toEqual([{ name: 'discord_button', args: { p_discord_id: '987', p_event: ID, p_choice: 'healer' } }])
    const body = await res.json()
    expect(body.type).toBe(4)
    expect(body.data.flags).toBe(64)
    expect(body.data.content).toBe("You're in as Healer for Molten Core.")
  })

  it('takes the user from a DM press too, and marks Can’t make it', async () => {
    const { send, calls } = await setup({ result: 'out', title: 'Molten Core' })
    const res = await send({ type: 3, data: { custom_id: customId(ID, 'out') }, user: { id: '55' } })
    expect(calls[0]!.args).toEqual({ p_discord_id: '55', p_event: ID, p_choice: 'out' })
    expect((await res.json()).data.content).toBe('Marked as not coming to Molten Core.')
  })

  it('points a stranger at the site', async () => {
    const { send } = await setup({ result: 'not_member' })
    expect((await (await send(press('tank'))).json()).data.content).toContain(SITE)
  })

  it('ignores a button that isn’t ours, without touching the database', async () => {
    const { send, calls } = await setup()
    const res = await send({ type: 3, data: { custom_id: 'something-else' }, member: { user: { id: '1' } } })
    expect((await res.json()).data.flags).toBe(64)
    expect(calls).toEqual([])
  })

  it('refuses another application’s interaction', async () => {
    const { send } = await setup()
    expect((await send({ ...press('tank'), application_id: 'other' })).status).toBe(401)
  })

  it('says so, quietly, when the database fails', async () => {
    const signer = await testSigner()
    const deps: InteractionDeps = { publicKey: signer.publicKey, db: { rpc: async () => { throw new Error('down') } }, siteUrl: SITE, log: () => {} }
    const body = JSON.stringify(press('dps'))
    const res = await handleInteraction(deps, new Request('https://x', { method: 'POST', body, headers: { 'X-Signature-Timestamp': '1', 'X-Signature-Ed25519': await signer.sign('1', body) } }))
    expect((await res.json()).data.content).toContain('Something went wrong')
  })
})
