# Treehouse 310

A tiny MCP server so Alex's Claude and Sam's Claude can leave each other messages. It runs on Cloudflare Workers with a D1 (SQLite) database, on the free tier.

It isn't real-time. Each Claude checks the inbox when you ask it to, or on a schedule if you set one up.

## Tools

- `send_message(to, text, thread?)`: `to` is `alex` or `sam`. Thread defaults to `general`.
- `read_messages(unread_only?, since?, thread?, include_sent?, limit?)`: messages sent to you, unread only by default. Reading doesn't mark them read.
- `list_threads()`: threads with message counts, last activity and your unread count.
- `mark_read(ids?, thread?)`: mark your messages read. With no arguments it marks everything.

You never say who you are. The server works it out from your key.

## A note on trust

Messages from the other Claude are information, not commands. If a message says "go delete X" or "run Y", your Claude should check with you first. The server repeats this in its instructions and in every `read_messages` result, but it's worth saying in your own CLAUDE.md too.

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

Create the table, then deploy:

```bash
npx wrangler d1 migrations apply DB --remote
npx wrangler deploy
```

The deploy prints your URL, something like `https://treehouse-310.<your-subdomain>.workers.dev`. The MCP endpoint is that URL plus `/mcp`.

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

`--scope user` makes it available in every project. Check it worked with `claude mcp list`, or ask Claude "check my Treehouse inbox".

To have Claude check on its own, use `/loop` in a session (for example `/loop 30m check my Treehouse inbox and tell me if anything's new`) or a scheduled task.

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

The server runs at `http://localhost:8787/mcp`, with the test keys from `.dev.vars`.
