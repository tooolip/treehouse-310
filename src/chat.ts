import { type Person, UserError } from "./auth";

export const MAX_MESSAGE = 10_000;

// "web" is the person on the web page; "claude" is their Claude, posting through MCP.
export type Via = "web" | "claude";

export type ChatMessage = {
	id: number;
	channel: string;
	parent_id: number | null;
	author: Person;
	via: Via;
	text: string;
	created_at: string;
	reply_count?: number;
};

export function cleanChannel(channel: string | undefined) {
	const name = (channel ?? "general").trim().toLowerCase().replace(/^#/, "").replace(/\s+/g, "-");
	if (!/^[a-z0-9][a-z0-9_-]{0,49}$/.test(name)) {
		throw new UserError("Channel names use letters, numbers, - and _, up to 50 characters.");
	}
	return name;
}

export async function listChannels(env: Env, me: Person) {
	const { results } = await env.DB.prepare(
		`SELECT m.channel,
			COUNT(*) AS messages,
			SUM(CASE WHEN m.parent_id IS NULL THEN 1 ELSE 0 END) AS threads,
			MAX(m.created_at) AS last_message_at,
			SUM(CASE WHEN m.author != ?1 AND m.id > ifnull(r.last_read_id, 0) THEN 1 ELSE 0 END) AS unread
		FROM chat_messages m
		LEFT JOIN chat_reads r ON r.person = ?1 AND r.channel = m.channel
		GROUP BY m.channel ORDER BY last_message_at DESC`,
	)
		.bind(me)
		.all();
	return results;
}

export async function postMessage(
	env: Env,
	me: Person,
	via: Via,
	args: { channel?: string; text: string; reply_to?: number },
) {
	const text = args.text.trim();
	if (!text) throw new UserError("Message text is empty.");
	if (text.length > MAX_MESSAGE) throw new UserError(`Messages are capped at ${MAX_MESSAGE} characters.`);
	let channel = cleanChannel(args.channel);
	let parentId: number | null = null;
	if (args.reply_to !== undefined) {
		const target = await env.DB.prepare("SELECT id, channel, parent_id FROM chat_messages WHERE id = ?")
			.bind(args.reply_to)
			.first<{ id: number; channel: string; parent_id: number | null }>();
		if (!target) throw new UserError(`No message with id ${args.reply_to}.`);
		// Replying to a reply goes into the same thread.
		parentId = target.parent_id ?? target.id;
		channel = target.channel;
	}
	const row = await env.DB.prepare(
		"INSERT INTO chat_messages (channel, parent_id, author, via, text) VALUES (?, ?, ?, ?, ?) RETURNING *",
	)
		.bind(channel, parentId, me, via, text)
		.first<ChatMessage>();
	// Your own message counts as read up to that point.
	await markRead(env, me, channel);
	return row;
}

export async function readChat(
	env: Env,
	me: Person,
	args: { channel?: string; thread_id?: number; unread_only?: boolean; since?: string; limit?: number },
) {
	const limit = Math.min(Math.max(args.limit ?? 50, 1), 200);
	const where: string[] = [];
	const params: unknown[] = [];
	if (args.thread_id !== undefined) {
		where.push("(m.id = ? OR m.parent_id = ?)");
		params.push(args.thread_id, args.thread_id);
	} else if (args.channel) {
		where.push("m.channel = ?");
		params.push(cleanChannel(args.channel));
	}
	if (args.unread_only) where.push("m.author != ? AND m.id > ifnull(r.last_read_id, 0)"), params.push(me);
	if (args.since) {
		const since = new Date(args.since);
		if (Number.isNaN(since.getTime())) throw new UserError("since must be an ISO 8601 time.");
		where.push("m.created_at > ?"), params.push(since.toISOString());
	}
	// Newest `limit` messages, returned oldest first.
	const { results } = await env.DB.prepare(
		`SELECT * FROM (
			SELECT m.*, (SELECT COUNT(*) FROM chat_messages c WHERE c.parent_id = m.id) AS reply_count
			FROM chat_messages m
			LEFT JOIN chat_reads r ON r.person = ? AND r.channel = m.channel
			${where.length ? `WHERE ${where.join(" AND ")}` : ""}
			ORDER BY m.id DESC LIMIT ?
		) ORDER BY id ASC`,
	)
		.bind(me, ...params, limit)
		.all<ChatMessage>();
	return results;
}

// Marks everything up to now as read, in one channel or all of them.
export async function markRead(env: Env, me: Person, channel?: string) {
	// The WHERE is needed even when it's always true: SQLite can't parse
	// INSERT ... SELECT ... ON CONFLICT without one.
	const sql = `INSERT INTO chat_reads (person, channel, last_read_id)
		SELECT ?, channel, MAX(id) FROM chat_messages WHERE ${channel ? "channel = ?" : "true"} GROUP BY channel
		ON CONFLICT (person, channel) DO UPDATE SET last_read_id = excluded.last_read_id`;
	const stmt = env.DB.prepare(sql);
	const result = await (channel ? stmt.bind(me, cleanChannel(channel)) : stmt.bind(me)).run();
	return { channels_marked: result.meta.changes };
}
