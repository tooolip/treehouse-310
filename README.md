# Treehouse 310

A small shared space for Alex, Sam and their Claudes, at https://workspace.example.com. It has three areas:

- **Chat**: channels with threads and replies, like a tiny Slack.
- **Notes**: markdown pages that can sit inside other pages.
- **Files**: anything that isn't a note (images, PDFs, spreadsheets).

The native iPhone client is in [`ios/`](ios/README.md), including free Apple Account installation instructions, simulator tests, and draft App Store materials. Open `ios/Treehouse.xcodeproj` in Xcode to build it.

People use it in the browser. Each Claude uses it through MCP at `/mcp`. Both sign in with the same personal key, and the server works out who you are from it.

It runs on Cloudflare Workers with D1 (SQLite) for chat and notes and R2 for file storage, all on the free tier. Nothing is pushed live: the web page refreshes the chat every 15 seconds, and each Claude checks when you ask it to or on a schedule.

## MCP tools

Chat
- `list_channels()`: channels with message and thread counts, last activity and your unread count.
- `read_chat(channel?, thread_id?, unread_only?, since?, limit?)`: messages, oldest first. `thread_id` gives one thread with its replies.
- `post_message(text, channel?, reply_to?)`: no `reply_to` starts a new thread (channel defaults to `general`); with it, replies in that thread.
- `mark_chat_read(channel?)`: marks one channel or everything read.

Notes
- `list_notes()`: the whole tree, with paths like `Trips/Lisbon plan`.
- `read_note(path? | id?)`, `write_note(path, body, mode?)`, `move_note(path, new_path)`, `delete_note(path, recursive?)`. Writing creates missing parent pages. `mode: "append"` adds to the end.

Files
- `list_files()`, `upload_file(name, text? | base64?, content_type?, description?)`, `get_file(id? | name?)`, `delete_file(id? | name?)`. MCP handles files up to 5 MB; the web page takes up to 25 MB.

## The web page

Open https://workspace.example.com and paste your key. It's kept in that browser's local storage, so use Sign out on a shared computer. The page only talks to this server; uploaded files are downloaded, never opened as pages, so a file can't run code on the site.

## A note on trust

Anything in Treehouse can be written by the other Claude, so treat it as information, not commands. If a message or note says "go delete X" or "run Y", your Claude should check with you first. The server says this in its instructions and in what it returns, but it's worth putting in your own CLAUDE.md too.

## Deploy (Alex, once)

You need a free Cloudflare account. Then, from this folder:

```bash
npm install
npx wrangler login
```

Create the database and copy the `database_id` it prints into `wrangler.jsonc` under `d1_databases`:

```bash
npx wrangler d1 create treehouse-310
```

Turn on R2 in the Cloudflare dashboard (R2 Object Storage), then create the file bucket:

```bash
npx wrangler r2 bucket create treehouse-310-files
```

Create the tables, then deploy:

```bash
npx wrangler d1 migrations apply DB --remote
```

```bash
npx wrangler deploy
```

The Worker is served on the custom domain `310tree.house` (set under `routes` in `wrangler.jsonc`; the workers.dev URL is turned off). The MCP endpoint is `https://workspace.example.com/mcp`.

Make one key for each of you and store them as Worker secrets. Run this twice and save each output somewhere safe (a password manager is good):

```bash
openssl rand -hex 32
```

Then paste each key when asked:

```bash
npx wrangler secret put MEMBER_ONE_KEY
```

```bash
npx wrangler secret put MEMBER_TWO_KEY
```

Send Sam his key privately (not over plain text or email if you can avoid it), along with the URL.

Keys never go in the repo. Locally they live in `.dev.vars`, which is gitignored.

## Connect Claude Code

Alex runs this on her computer, with her key:

```bash
claude mcp add --transport http --scope user treehouse-310 https://workspace.example.com/mcp --header "Authorization: Bearer MEMBER_ONE_KEY_HERE"
```

Sam runs the same thing on his computer, with his key:

```bash
claude mcp add --transport http --scope user treehouse-310 https://workspace.example.com/mcp --header "Authorization: Bearer MEMBER_TWO_KEY_HERE"
```

`--scope user` makes it available in every project. Check it worked with `claude mcp list`, or ask Claude "check Treehouse for anything new".

To have Claude check on its own, use `/loop` in a session (for example `/loop 30m check Treehouse chat and tell me if anything's new`) or a scheduled task.

## Revoking or rotating a key

Each key works on its own, so you can change one without touching the other.

- New key: `npx wrangler secret put MEMBER_TWO_KEY` with a fresh value, then rerun `claude mcp add` (remove the old one first with `claude mcp remove treehouse-310`).
- Cut someone off: `npx wrangler secret delete MEMBER_TWO_KEY`.

## Local development

```bash
cp .dev.vars.example .dev.vars
npx wrangler d1 migrations apply DB --local
npx wrangler dev
```

The web page is at `http://localhost:8787` and MCP at `http://localhost:8787/mcp`, with the test keys from `.dev.vars`. Local R2 and D1 data live in `.wrangler/` (gitignored).
