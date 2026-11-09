import { describe, expect, it } from 'vitest'
import { testSigner } from './testSigner.ts'
import { verifyDiscordSignature } from './verify.ts'

describe('verifyDiscordSignature', () => {
  it('accepts Discord’s signature and nothing else', async () => {
    const { publicKey, sign } = await testSigner()
    const body = '{"type":1}'
    const sig = await sign('1700000000', body)
    expect(await verifyDiscordSignature(publicKey, sig, '1700000000', body)).toBe(true)
    expect(await verifyDiscordSignature(publicKey, sig, '1700000001', body)).toBe(false) // another timestamp
    expect(await verifyDiscordSignature(publicKey, sig, '1700000000', '{"type":2}')).toBe(false) // another body
    expect(await verifyDiscordSignature(publicKey, sig.replace(/^./, (c) => (c === '0' ? '1' : '0')), '1700000000', body)).toBe(false)
    expect(await verifyDiscordSignature(publicKey, null, '1700000000', body)).toBe(false)
    expect(await verifyDiscordSignature(publicKey, sig, null, body)).toBe(false)
    expect(await verifyDiscordSignature(publicKey, 'zz', '1700000000', body)).toBe(false)
  })

  it('refuses a signature from another key, and a malformed public key', async () => {
    const a = await testSigner()
    const b = await testSigner()
    const sig = await b.sign('1', 'x')
    expect(await verifyDiscordSignature(a.publicKey, sig, '1', 'x')).toBe(false)
    expect(await verifyDiscordSignature('not-hex', sig, '1', 'x')).toBe(false)
  })
})
