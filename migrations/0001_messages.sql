CREATE TABLE messages (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	sender TEXT NOT NULL,
	recipient TEXT NOT NULL,
	thread TEXT NOT NULL DEFAULT 'general',
	text TEXT NOT NULL,
	created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
	read_at TEXT
);

CREATE INDEX idx_messages_recipient ON messages (recipient, read_at);
CREATE INDEX idx_messages_thread ON messages (thread, created_at);
