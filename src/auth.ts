export const PEOPLE = ["alex", "sam"] as const;
export type Person = (typeof PEOPLE)[number];

async function digest(value: string) {
	return crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
}

// Works out who is calling from their key. Each person has their own secret,
// so one can be rotated or revoked without touching the other.
export async function identify(request: Request, env: Env): Promise<Person | null> {
	const header = request.headers.get("Authorization") ?? "";
	const match = header.match(/^Bearer\s+(.+)$/i);
	if (!match) return null;
	const given = await digest(match[1].trim());
	const keys: Record<Person, string | undefined> = { alex: env.MEMBER_ONE_KEY, sam: env.MEMBER_TWO_KEY };
	for (const person of PEOPLE) {
		const key = keys[person];
		if (key && crypto.subtle.timingSafeEqual(given, await digest(key))) return person;
	}
	return null;
}

// Bad input from a caller. The message is safe to show them.
export class UserError extends Error {}
