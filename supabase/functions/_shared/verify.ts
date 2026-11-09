// Discord signs every interaction with the app's Ed25519 key: X-Signature-Ed25519 over timestamp + raw body.
// Web Crypto does Ed25519 in Deno (Supabase Edge Functions) and in Node, so nothing extra is needed.

function hexBytes(hex: string): Uint8Array<ArrayBuffer> | null {
  if (!/^(?:[0-9a-f]{2})+$/i.test(hex)) return null
  const out = new Uint8Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return out
}

const keys = new Map<string, Promise<CryptoKey>>()

function publicKey(hex: string): Promise<CryptoKey> {
  let key = keys.get(hex)
  if (!key) {
    const raw = hexBytes(hex)
    if (!raw || raw.length !== 32) return Promise.reject(new Error('DISCORD_PUBLIC_KEY is not a 64-character hex key'))
    key = crypto.subtle.importKey('raw', raw, { name: 'Ed25519' }, false, ['verify'])
    keys.set(hex, key)
  }
  return key
}

/** True only when the signature is Discord's (the app's public key) over this timestamp and body. */
export async function verifyDiscordSignature(publicKeyHex: string, signatureHex: string | null, timestamp: string | null, body: string): Promise<boolean> {
  const sig = signatureHex ? hexBytes(signatureHex) : null
  if (!sig || sig.length !== 64 || !timestamp) return false
  try {
    return await crypto.subtle.verify({ name: 'Ed25519' }, await publicKey(publicKeyHex), sig, new TextEncoder().encode(timestamp + body))
  } catch {
    return false
  }
}
