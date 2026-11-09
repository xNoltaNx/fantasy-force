// Just enough of Deno and Supabase's Edge Runtime for `tsc` to check supabase/functions (Deno isn't installed
// here). It sits outside supabase/functions, so it never ships with them.

declare namespace Deno {
  function serve(handler: (req: Request) => Response | Promise<Response>): unknown
  const env: { get(name: string): string | undefined }
}

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void }
