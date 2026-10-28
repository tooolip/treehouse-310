import { type Person, UserError } from "./auth";

export const MAX_NOTE = 200_000;

type NoteMeta = {
	id: number;
	parent_id: number | null;
	title: string;
	updated_by: Person;
	updated_at: string;
};

export type Note = NoteMeta & { body: string; created_by: Person; created_at: string };

export type NoteTree = NoteMeta & { path: string; children: NoteTree[] };

// Notes are addressed by path, like "Trips/Lisbon plan". Titles can't contain "/".
export function splitPath(path: string) {
	const parts = path
		.split("/")
		.map((p) => p.trim())
		.filter(Boolean);
	if (!parts.length) throw new UserError("Note path is empty.");
	for (const part of parts) {
		if (part.length > 120) throw new UserError("Note titles are capped at 120 characters.");
	}
	return parts;
}

// There are only ever a few hundred notes, so it's simplest to load the
// titles once and work out paths in memory.
async function loadMeta(env: Env) {
	const { results } = await env.DB.prepare(
		"SELECT id, parent_id, title, updated_by, updated_at FROM notes ORDER BY title COLLATE NOCASE",
	).all<NoteMeta>();
	return results;
}

function pathOf(meta: NoteMeta[], id: number) {
	const byId = new Map(meta.map((n) => [n.id, n]));
	const parts: string[] = [];
	for (let n = byId.get(id); n; n = n.parent_id === null ? undefined : byId.get(n.parent_id)) {
		parts.unshift(n.title);
	}
	return parts.join("/");
}

function findByPath(meta: NoteMeta[], parts: string[]) {
	let parentId: number | null = null;
	let found: NoteMeta | undefined;
	for (const part of parts) {
		found = meta.find((n) => n.parent_id === parentId && n.title === part);
		if (!found) return undefined;
		parentId = found.id;
	}
	return found;
}

export async function listNotes(env: Env) {
	const meta = await loadMeta(env);
	const nodes = new Map<number, NoteTree>(meta.map((n) => [n.id, { ...n, path: "", children: [] }]));
	const roots: NoteTree[] = [];
	for (const node of nodes.values()) {
		node.path = pathOf(meta, node.id);
		const parent = node.parent_id === null ? undefined : nodes.get(node.parent_id);
		(parent ? parent.children : roots).push(node);
	}
	return roots;
}

export async function readNote(env: Env, ref: { id?: number; path?: string }) {
	const meta = await loadMeta(env);
	const id = ref.id ?? (ref.path ? findByPath(meta, splitPath(ref.path))?.id : undefined);
	const note = id === undefined ? null : await env.DB.prepare("SELECT * FROM notes WHERE id = ?").bind(id).first<Note>();
	if (!note) throw new UserError(`No note at ${ref.path ?? `id ${ref.id}`}.`);
	const children = meta.filter((n) => n.parent_id === note.id).map((n) => n.title);
	return { ...note, path: pathOf(meta, note.id), children };
}

// Creates the note (and any missing parent pages) or updates it if it exists.
export async function writeNote(
	env: Env,
	me: Person,
	args: { path: string; body: string; mode?: "replace" | "append" },
) {
	if (args.body.length > MAX_NOTE) throw new UserError(`Notes are capped at ${MAX_NOTE} characters.`);
	const parts = splitPath(args.path);
	const meta = await loadMeta(env);
	let parentId: number | null = null;
	for (const part of parts.slice(0, -1)) {
		let parent = meta.find((n) => n.parent_id === parentId && n.title === part);
		if (!parent) {
			parent = (await env.DB.prepare(
				"INSERT INTO notes (parent_id, title, created_by, updated_by) VALUES (?, ?, ?, ?) RETURNING id, parent_id, title, updated_by, updated_at",
			)
				.bind(parentId, part, me, me)
				.first<NoteMeta>())!;
			meta.push(parent);
		}
		parentId = parent.id;
	}
	const title = parts[parts.length - 1];
	const existing = meta.find((n) => n.parent_id === parentId && n.title === title);
	if (!existing) {
		const note = await env.DB.prepare(
			"INSERT INTO notes (parent_id, title, body, created_by, updated_by) VALUES (?, ?, ?, ?, ?) RETURNING id",
		)
			.bind(parentId, title, args.body, me, me)
			.first<{ id: number }>();
		return { created: true, id: note!.id, path: parts.join("/") };
	}
	const sql =
		args.mode === "append"
			? "UPDATE notes SET body = body || char(10) || ?, updated_by = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?"
			: "UPDATE notes SET body = ?, updated_by = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?";
	await env.DB.prepare(sql).bind(args.body, me, existing.id).run();
	return {
		created: false,
		id: existing.id,
		path: parts.join("/"),
		previously_updated_by: existing.updated_by,
		previously_updated_at: existing.updated_at,
	};
}

export async function moveNote(env: Env, me: Person, args: { path: string; new_path: string }) {
	const meta = await loadMeta(env);
	const note = findByPath(meta, splitPath(args.path));
	if (!note) throw new UserError(`No note at ${args.path}.`);
	const target = splitPath(args.new_path);
	const parent = target.length > 1 ? findByPath(meta, target.slice(0, -1)) : null;
	if (parent === undefined) throw new UserError(`The new parent ${target.slice(0, -1).join("/")} doesn't exist yet.`);
	// A page can't move inside itself.
	for (let p: NoteMeta | undefined = parent ?? undefined; p; p = meta.find((n) => n.id === p!.parent_id)) {
		if (p.id === note.id) throw new UserError("A note can't be moved inside itself.");
	}
	const title = target[target.length - 1];
	const clash = meta.find((n) => n.parent_id === (parent?.id ?? null) && n.title === title && n.id !== note.id);
	if (clash) throw new UserError(`There's already a note at ${target.join("/")}.`);
	await env.DB.prepare(
		"UPDATE notes SET parent_id = ?, title = ?, updated_by = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?",
	)
		.bind(parent?.id ?? null, title, me, note.id)
		.run();
	return { id: note.id, path: target.join("/") };
}

export async function deleteNote(env: Env, args: { path: string; recursive?: boolean }) {
	const meta = await loadMeta(env);
	const note = findByPath(meta, splitPath(args.path));
	if (!note) throw new UserError(`No note at ${args.path}.`);
	const ids = [note.id];
	for (let i = 0; i < ids.length; i++) {
		ids.push(...meta.filter((n) => n.parent_id === ids[i]).map((n) => n.id));
	}
	if (ids.length > 1 && !args.recursive) {
		throw new UserError(`${args.path} has ${ids.length - 1} page(s) inside it. Pass recursive to delete them too.`);
	}
	// Children first, so no row is left pointing at a deleted parent.
	await env.DB.batch(ids.reverse().map((id) => env.DB.prepare("DELETE FROM notes WHERE id = ?").bind(id)));
	return { deleted: ids.length };
}
