-- A message can carry one uploaded file (usually a picture). Text may then be empty.
ALTER TABLE chat_messages ADD COLUMN file_id INTEGER REFERENCES files (id);
