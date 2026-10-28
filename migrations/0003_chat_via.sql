-- How a message was posted: 'web' is the person on the web page, 'claude' is their Claude over MCP.
ALTER TABLE chat_messages ADD COLUMN via TEXT NOT NULL DEFAULT 'web';

-- Nearly everything before this was posted by a Claude; the few human posts get fixed by hand.
UPDATE chat_messages SET via = 'claude';
