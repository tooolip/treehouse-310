import { type Person, UserError } from "./auth";

export const MAX_FILE = 25 * 1024 * 1024;

export type FileRow = {
	id: number;
	name: string;
	description: string;
	content_type: string;
	size: number;
	r2_key: string;
	uploaded_by: Person;
	created_at: string;
};

export function isText(contentType: string) {
	return /^text\/|[/+](json|xml|csv|markdown|yaml|javascript)\b/.test(contentType);
}

function cleanName(name: string) {
	const clean = name.trim().replace(/[\\/]/g, "_");
	if (!clean || clean.length > 200) throw new UserError("File names need 1 to 200 characters.");
	return clean;
}

function publicFields({ r2_key: _, ...rest }: FileRow) {
	return rest;
}

export async function listFiles(env: Env) {
	const { results } = await env.DB.prepare("SELECT * FROM files ORDER BY created_at DESC").all<FileRow>();
	return results.map(publicFields);
}

export async function uploadFile(
	env: Env,
	me: Person,
	args: { name: string; content_type?: string; description?: string; data: ArrayBuffer | Uint8Array },
) {
	const name = cleanName(args.name);
	if (args.data.byteLength > MAX_FILE) throw new UserError(`Files are capped at ${MAX_FILE / 1024 / 1024} MB.`);
	const contentType = args.content_type || "application/octet-stream";
	const key = crypto.randomUUID();
	await env.FILES.put(key, args.data, { httpMetadata: { contentType } });
	const row = await env.DB.prepare(
		"INSERT INTO files (name, description, content_type, size, r2_key, uploaded_by) VALUES (?, ?, ?, ?, ?, ?) RETURNING *",
	)
		.bind(name, args.description ?? "", contentType, args.data.byteLength, key, me)
		.first<FileRow>();
	return publicFields(row!);
}

async function findFile(env: Env, ref: { id?: number; name?: string }) {
	const row =
		ref.id !== undefined
			? await env.DB.prepare("SELECT * FROM files WHERE id = ?").bind(ref.id).first<FileRow>()
			: ref.name
				? // Several uploads can share a name; the newest wins.
					await env.DB.prepare("SELECT * FROM files WHERE name = ? ORDER BY id DESC LIMIT 1").bind(ref.name).first<FileRow>()
				: null;
	if (!row) throw new UserError(`No file ${ref.name ?? `with id ${ref.id}`}.`);
	return row;
}

export async function getFile(env: Env, ref: { id?: number; name?: string }) {
	const row = await findFile(env, ref);
	const object = await env.FILES.get(row.r2_key);
	if (!object) throw new UserError(`The bytes for ${row.name} are missing from storage.`);
	return { meta: publicFields(row), object };
}

export async function deleteFile(env: Env, ref: { id?: number; name?: string }) {
	const row = await findFile(env, ref);
	await env.FILES.delete(row.r2_key);
	await env.DB.prepare("DELETE FROM files WHERE id = ?").bind(row.id).run();
	return { deleted: publicFields(row) };
}
