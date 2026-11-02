export type Person = string;

async function digest(value: string) {
 return crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
}

// Member IDs and their secret-binding names are private deployment data. Keep IDs stable so
// existing messages, notes, files, and read markers stay associated correctly.
export async function identify(request: Request, env: Env): Promise<Person | null> {
 const match = (request.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i);
 if (!match || !env.MEMBER_BINDINGS_JSON) return null;
 let members: unknown;
 try { members = JSON.parse(env.MEMBER_BINDINGS_JSON); } catch { return null; }
 if (!members || typeof members !== "object" || Array.isArray(members)) return null;
 const entries = Object.entries(members);
 const bindings = env as unknown as Record<string, unknown>;
 if (entries.some(([id, binding]) => !id || typeof binding !== "string" ||
  !/^[A-Z][A-Z0-9_]*$/.test(binding))) return null;
 const given = await digest(match[1].trim());
 for (const [id, binding] of entries) {
  const key = bindings[binding as string];
  if (typeof key !== "string" || !key.trim()) continue;
  if (crypto.subtle.timingSafeEqual(given, await digest(key))) return id;
 }
 return null;
}

// Bad input from a caller. The message is safe to show them.
export class UserError extends Error {}
