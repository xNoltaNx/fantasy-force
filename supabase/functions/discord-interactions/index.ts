// Discord's Interactions Endpoint URL: https://<project>.supabase.co/functions/v1/discord-interactions
// Deployed with JWT checks off (Discord signs its requests instead). The logic is in ../_shared, tested by vitest.

import { handleInteraction } from '../_shared/interactions.ts'
import { interactionDeps } from '../_shared/setup.ts'

Deno.serve((req) => handleInteraction(interactionDeps((name) => Deno.env.get(name), fetch), req))
