-- Auth0's verified subject is the owner. Names, emails and client-supplied IDs
-- are never used for authorization. No password or private content is stored.
CREATE TABLE settings (
    subject TEXT PRIMARY KEY NOT NULL,
    revision INTEGER NOT NULL CHECK (revision > 0),
    document TEXT NOT NULL CHECK (length(document) <= 8192),
    updated_at TEXT NOT NULL
);
