import { type Person, UserError } from "./auth";
import * as chat from "./chat";
import * as files from "./files";
import * as notes from "./notes";

// JSON API for the web page. Same logic as the MCP tools.

function json(value: unknown, status = 200) {
	return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}

async function body<T>(request: Request): Promise<T> {
	try {
		return (await request.json()) as T;
	} catch {
		throw new UserError("Request body isn't valid JSON.");
	}
}

function intParam(value: string | null) {
	if (value === null || value === "") return undefined;
	const n = Number(value);
	if (!Number.isInteger(n)) throw new UserError(`${value} isn't a whole number.`);
	return n;
}

async function route(request: Request, env: Env, me: Person, url: URL): Promise<Response> {
	const { pathname: path, searchParams: q } = url;
	const method = request.method;

	if (path === "/api/me" && method === "GET") return json({ me });

	if (path === "/api/chat/channels" && method === "GET") return json({ channels: await chat.listChannels(env, me) });
	if (path === "/api/chat/messages" && method === "GET") {
		const messages = await chat.readChat(env, me, {
			channel: q.get("channel") ?? undefined,
			thread_id: intParam(q.get("thread_id")),
			limit: intParam(q.get("limit")) ?? 200,
		});
		return json({ messages });
	}
	if (path === "/api/chat/messages" && method === "POST") {
		return json({ posted: await chat.postMessage(env, me, "web", await body(request)) });
	}
	if (path === "/api/chat/read" && method === "POST") {
		return json(await chat.markRead(env, me, (await body<{ channel?: string }>(request)).channel));
	}

	if (path === "/api/notes" && method === "GET") return json({ notes: await notes.listNotes(env) });
	if (path === "/api/notes/read" && method === "GET") {
		return json(await notes.readNote(env, { id: intParam(q.get("id")), path: q.get("path") ?? undefined }));
	}
	if (path === "/api/notes" && method === "PUT") return json(await notes.writeNote(env, me, await body(request)));
	if (path === "/api/notes/move" && method === "POST") return json(await notes.moveNote(env, me, await body(request)));
	if (path === "/api/notes/delete" && method === "POST") return json(await notes.deleteNote(env, await body(request)));

	if (path === "/api/files" && method === "GET") return json({ files: await files.listFiles(env) });
	if (path === "/api/files" && method === "POST") {
		const form = await request.formData();
		const file = form.get("file");
		if (!(file instanceof File)) throw new UserError("Choose a file to upload.");
		const uploaded = await files.uploadFile(env, me, {
			name: file.name,
			content_type: file.type,
			description: String(form.get("description") ?? ""),
			data: await file.arrayBuffer(),
		});
		return json({ uploaded });
	}
	const fileMatch = path.match(/^\/api\/files\/(\d+)\/(content|delete)$/);
	if (fileMatch && fileMatch[2] === "content" && method === "GET") {
		const { meta, object } = await files.getFile(env, { id: Number(fileMatch[1]) });
		return new Response(object.body, {
			headers: {
				"Content-Type": meta.content_type,
				"Content-Disposition": `attachment; filename*=UTF-8''${encodeURIComponent(meta.name)}`,
				// Uploaded files could be anything, including HTML. Never let one run as a page here.
				"Content-Security-Policy": "sandbox",
				"X-Content-Type-Options": "nosniff",
				"Cache-Control": "no-store",
			},
		});
	}
	if (fileMatch && fileMatch[2] === "delete" && method === "POST") {
		return json(await files.deleteFile(env, { id: Number(fileMatch[1]) }));
	}

	return json({ error: "Not found" }, 404);
}

export async function handleApi(request: Request, env: Env, me: Person, url: URL) {
	try {
		return await route(request, env, me, url);
	} catch (err) {
		if (err instanceof UserError) return json({ error: err.message }, 400);
		throw err;
	}
}
