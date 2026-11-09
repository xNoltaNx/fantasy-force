// For the tests only: a key pair standing in for the Discord app's, and a signer like Discord's.

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('')

export async function testSigner() {
  const pair = (await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify'])) as CryptoKeyPair
  const publicKey = hex(await crypto.subtle.exportKey('raw', pair.publicKey) as ArrayBuffer)
  const sign = async (timestamp: string, body: string) =>
    hex(await crypto.subtle.sign({ name: 'Ed25519' }, pair.privateKey, new TextEncoder().encode(timestamp + body)))
  return { publicKey, sign }
}
