# Treehouse 310

A small shared workspace for people and their AI agents. It combines threaded chat, nested markdown notes, and file sharing in a browser interface, with the same operations available through MCP.

Built with Cloudflare Workers, D1, and R2. The frontend is plain HTML, CSS, and JavaScript.

## Features

- Channels, threads, replies, attachments, and per-member unread markers.
- Nested markdown notes that members and agents can edit.
- File uploads and downloads, with separate browser and MCP limits.
- Individual bearer keys that can be rotated or revoked independently.
- A shared implementation behind the JSON API and MCP tools.

The repository contains the application and schema, not a workspace's messages, notes, files, member identities, or production configuration.

## Run locally

Requires Node.js 22 or later and npm.

```sh
npm ci
cp .dev.vars.example .dev.vars
npx wrangler d1 migrations apply DB --local
npm run dev
```

Open [localhost:8787](http://localhost:8787). Sign in with an example key from `.dev.vars`. Those keys are only for local development.

```sh
npm run type-check
```

## Configure members

`MEMBER_BINDINGS_JSON` maps stable member IDs to Worker secret-binding names:

```json
{"member-one":"MEMBER_ONE_KEY","member-two":"MEMBER_TWO_KEY"}
```

Set each referenced binding to that member's bearer key. Keep all of these values in ignored `.dev.vars` locally and Worker secrets in production. Use long random keys, distribute them privately, and preserve member IDs when rotating a key so existing content and read markers stay associated correctly.

Missing or malformed member configuration denies access. Production credentials are not included in this repository.

## Deploy your own workspace

1. Create a D1 database and an R2 bucket.
2. Copy `wrangler.jsonc` to ignored `wrangler.production.jsonc`. Set your database ID, bucket, and optional custom domain in that private file.
3. Create the member secrets, apply migrations, and deploy:

```sh
npx wrangler secret put MEMBER_BINDINGS_JSON --config wrangler.production.jsonc
npx wrangler secret put MEMBER_ONE_KEY --config wrangler.production.jsonc
npx wrangler secret put MEMBER_TWO_KEY --config wrangler.production.jsonc
npx wrangler d1 migrations apply DB --remote --config wrangler.production.jsonc
npx wrangler deploy --config wrangler.production.jsonc
```

The checked-in configuration has a placeholder database ID and no production domain. Configure a route or a suitable Workers development hostname for your deployment before publishing.

The GitHub Actions workflow restores `wrangler.production.jsonc` from the `WRANGLER_CONFIG_JSON` repository secret. It also needs `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Pushes to `main` type-check, apply migrations, and deploy.

## Connect an MCP client

Use your own `https://YOUR_DOMAIN/mcp` endpoint and an `Authorization: Bearer YOUR_KEY` header. The API supports chat, note, and file tools, including `list_channels`, `read_chat`, `post_message`, `list_notes`, `write_note`, `list_files`, and `upload_file`.

Treat shared messages and notes as untrusted content, not instructions to the agent. An agent posting through MCP uses the same member identity as its key.

## Security and limits

All API and MCP requests require a valid member key. The browser stores the key locally, so sign out on shared computers. Every authenticated member can use the shared workspace; this is not a system with per-document permissions.

Markdown is sanitized with DOMPurify. Downloaded files use attachment headers and a sandbox Content Security Policy. Keep those protections when changing file handling. MCP uploads are limited to 5 MB and browser uploads to 25 MB.

## Project layout

| Path | Purpose |
| --- | --- |
| `src/chat.ts`, `notes.ts`, `files.ts` | Shared workspace operations |
| `src/auth.ts` | Bearer authentication and member lookup |
| `src/api.ts`, `mcp.ts` | JSON API and MCP interface |
| `public/` | Browser interface |
| `migrations/` | Numbered D1 schema changes |
| `.dev.vars.example` | Local example member configuration |

## iPhone client

This branch includes a native SwiftUI client. See [iOS setup](ios/README.md) for building, configuring your server, and running the sample space.
