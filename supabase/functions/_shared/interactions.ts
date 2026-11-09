// discord-interactions: Discord's Interactions Endpoint URL. Checks Discord's signature, answers the PING,
// and turns a button press into a sign-up (public.discord_button), answered with one line only the presser sees.
// The post's counts then refresh through the sign-ups trigger, like a sign-up made on the site.

import { buttonReply, parseCustomId, type ButtonResult } from './message.ts'
import type { Db } from './rest.ts'
import { verifyDiscordSignature } from './verify.ts'

export interface InteractionDeps {
  publicKey: string
  applicationId?: string
  db: Db
  siteUrl: string
  log: (...a: unknown[]) => void
}

const PING = 1
const MESSAGE_COMPONENT = 3
const PONG = 1
const CHANNEL_MESSAGE = 4
const EPHEMERAL = 64

interface Interaction {
  type: number
  application_id?: string
  data?: { custom_id?: string }
  member?: { user?: { id?: string } }
  user?: { id?: string }
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const say = (content: string) => json({ type: CHANNEL_MESSAGE, data: { content, flags: EPHEMERAL, allowed_mentions: { parse: [] } } })

export async function handleInteraction(deps: InteractionDeps, req: Request): Promise<Response> {
  if (req.method !== 'POST') return new Response('POST only', { status: 405 })
  const body = await req.text()
  const ok = await verifyDiscordSignature(deps.publicKey, req.headers.get('X-Signature-Ed25519'), req.headers.get('X-Signature-Timestamp'), body)
  if (!ok) return new Response('Bad request signature', { status: 401 })

  let i: Interaction
  try { i = JSON.parse(body) as Interaction } catch { return new Response('Bad request', { status: 400 }) }
  if (deps.applicationId && i.application_id && i.application_id !== deps.applicationId) return new Response('Wrong application', { status: 401 })
  if (i.type === PING) return json({ type: PONG })
  if (i.type !== MESSAGE_COMPONENT) return say('Use the buttons under an event.')

  const press = parseCustomId(i.data?.custom_id ?? '')
  const discordId = i.member?.user?.id ?? i.user?.id
  if (!press || !discordId) return say('That button no longer works.')
  try {
    const result = await deps.db.rpc<ButtonResult>('discord_button', { p_discord_id: discordId, p_event: press.eventId, p_choice: press.choice })
    return say(buttonReply(result, deps.siteUrl))
  } catch (e) {
    deps.log('discord_button failed', press, e)
    return say('Something went wrong. Try again, or sign up on the guild site.')
  }
}
