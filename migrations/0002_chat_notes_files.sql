-- Chat: channels hold top-level messages; a reply points at its thread's first message.
CREATE TABLE chat_messages (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	channel TEXT NOT NULL DEFAULT 'general',
	parent_id INTEGER REFERENCES chat_messages (id),
	author TEXT NOT NULL,
	text TEXT NOT NULL,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX idx_chat_channel ON chat_messages (channel, id);
CREATE INDEX idx_chat_parent ON chat_messages (parent_id, id);

-- Highest message id each person has read in each channel.
CREATE TABLE chat_reads (
	person TEXT NOT NULL,
	channel TEXT NOT NULL,
	last_read_id INTEGER NOT NULL,
	PRIMARY KEY (person, channel)
);

-- Old one-to-one messages become chat messages, one channel per old thread.
INSERT INTO chat_messages (id, channel, author, text, created_at)
	SELECT id, thread, sender, text, created_at FROM messages;

DROP TABLE messages;

-- Notes: markdown pages that can sit inside other pages.
CREATE TABLE notes (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	parent_id INTEGER REFERENCES notes (id),
	title TEXT NOT NULL,
	body TEXT NOT NULL DEFAULT '',
	created_by TEXT NOT NULL,
	updated_by TEXT NOT NULL,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE UNIQUE INDEX idx_notes_sibling_title ON notes (ifnull(parent_id, 0), title);

-- Files: the bytes live in R2 under r2_key; this is the listing.
CREATE TABLE files (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL,
	description TEXT NOT NULL DEFAULT '',
	content_type TEXT NOT NULL,
	size INTEGER NOT NULL,
	r2_key TEXT NOT NULL UNIQUE,
	uploaded_by TEXT NOT NULL,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX idx_files_name ON files (name);
