// Remembers the addon's saved file in this browser (Chrome and Edge: the File System Access API), so My
// characters can read it again on each visit. The file handle lives in IndexedDB, per member; the browser asks
// once per visit, or never again after "Allow on every visit".

type Permission = 'granted' | 'denied' | 'prompt'
interface ReadHandle {
  name: string
  getFile(): Promise<File>
  queryPermission?(o: { mode: 'read' }): Promise<Permission>
  requestPermission?(o: { mode: 'read' }): Promise<Permission>
}
type Picker = (o: object) => Promise<ReadHandle[]>

const DB = 'fantasy-force'
const STORE = 'saved-file'

export const canRemember = () => typeof window !== 'undefined' && typeof (window as unknown as { showOpenFilePicker?: Picker }).showOpenFilePicker === 'function' && typeof indexedDB !== 'undefined'

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const r = indexedDB.open(DB, 1)
    r.onupgradeneeded = () => r.result.createObjectStore(STORE)
    r.onsuccess = () => resolve(r.result)
    r.onerror = () => reject(r.error)
  })
}

async function tx<T>(mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest): Promise<T> {
  const db = await open()
  try {
    return await new Promise<T>((resolve, reject) => {
      const req = run(db.transaction(STORE, mode).objectStore(STORE))
      req.onsuccess = () => resolve(req.result as T)
      req.onerror = () => reject(req.error)
    })
  } finally { db.close() }
}

export interface Remembered { handle: ReadHandle; imported: number } // imported: the file's lastModified at the last import

export async function recall(memberId: string): Promise<Remembered | null> {
  try { return (await tx<Remembered | undefined>('readonly', (s) => s.get(memberId))) ?? null } catch { return null }
}
export async function remember(memberId: string, r: Remembered) {
  try { await tx('readwrite', (s) => s.put(r, memberId)) } catch { /* private window: works for this visit only */ }
}
export async function forget(memberId: string) {
  try { await tx('readwrite', (s) => s.delete(memberId)) } catch { /* nothing kept */ }
}

/** The file picker; null when cancelled. */
export async function pick(): Promise<ReadHandle | null> {
  try {
    const [h] = await (window as unknown as { showOpenFilePicker: Picker }).showOpenFilePicker({
      id: 'ff-saved-file',
      types: [{ description: 'The addon\'s saved file', accept: { 'text/plain': ['.lua'] } }],
    })
    return h ?? null
  } catch { return null }
}

/** Whether the file can be read now; with ask (needs a click), the browser may ask. */
export async function allowed(h: ReadHandle, ask: boolean): Promise<boolean> {
  const o = { mode: 'read' as const }
  if (!h.queryPermission) return true
  if ((await h.queryPermission(o)) === 'granted') return true
  return ask && !!h.requestPermission && (await h.requestPermission(o)) === 'granted'
}
