// Called only by the guild's own database (triggers and the reminder cron job, through pg_net), with the
// shared secret from public.discord_state. Answers at once and finishes the Discord work in the background.

import { announceRequest } from '../_shared/announce.ts'
import { announceDeps } from '../_shared/setup.ts'

Deno.serve(async (req) => {
  const { response, work } = await announceRequest(announceDeps((name) => Deno.env.get(name), fetch), req)
  if (work) {
    if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(work)
    else await work
  }
  return response
})
