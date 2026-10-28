import { createMcpHandler } from "agents/mcp/server";
import { handleApi } from "./api";
import { identify } from "./auth";
import { createServer } from "./mcp";

// The web page itself (public/) is served as static assets before this runs.
// Everything that reaches the Worker needs a key.
export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext) {
		const url = new URL(request.url);
		const isMcp = url.pathname === "/mcp";
		if (!isMcp && !url.pathname.startsWith("/api/")) return new Response("Not found", { status: 404 });

		const me = await identify(request, env);
		if (!me) {
			return new Response("Unauthorized", {
				status: 401,
				headers: { "WWW-Authenticate": "Bearer" },
			});
		}
		if (isMcp) return createMcpHandler(() => createServer(env, me))(request, env, ctx);
		return handleApi(request, env, me, url);
	},
} satisfies ExportedHandler<Env>;
