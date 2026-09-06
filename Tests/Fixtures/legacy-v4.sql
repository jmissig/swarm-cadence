-- Synthetic schema-only v4 fixture: frozen before source-artifact migrations.
CREATE TABLE raw_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    relative_path TEXT NOT NULL UNIQUE,
    raw_file_name TEXT NOT NULL,
    manifest_file_name TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    bytes INTEGER NOT NULL,
    fetched_at TEXT NOT NULL,
    adapter TEXT NOT NULL,
    account TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    api_version TEXT NOT NULL,
    "limit" INTEGER NOT NULL,
    "offset" INTEGER NOT NULL,
    http_status INTEGER NOT NULL,
    api_meta_code INTEGER,
    returned_count INTEGER,
    total_count INTEGER,
    imported_at TEXT NOT NULL
);

CREATE TABLE venues (
    venue_id TEXT PRIMARY KEY,
    name TEXT,
    lat REAL,
    lng REAL,
    categories_json TEXT,
    raw_json TEXT,
    updated_at TEXT NOT NULL
);

CREATE TABLE checkins (
    checkin_id TEXT PRIMARY KEY,
    account TEXT NOT NULL,
    source_adapter TEXT NOT NULL,
    created_at_unix INTEGER,
    created_at_iso TEXT,
    venue_id TEXT REFERENCES venues(venue_id),
    raw_file_id INTEGER NOT NULL REFERENCES raw_files(id),
    raw_json TEXT NOT NULL,
    imported_at TEXT NOT NULL
);

CREATE TABLE categories (
    category_id TEXT PRIMARY KEY,
    name TEXT,
    plural_name TEXT,
    short_name TEXT,
    icon_json TEXT,
    updated_at TEXT NOT NULL
);

CREATE TABLE checkin_categories (
    checkin_id TEXT NOT NULL REFERENCES checkins(checkin_id) ON DELETE CASCADE,
    category_id TEXT NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
    venue_id TEXT REFERENCES venues(venue_id),
    account TEXT NOT NULL,
    raw_file_id INTEGER NOT NULL REFERENCES raw_files(id),
    ordinal INTEGER NOT NULL,
    PRIMARY KEY (checkin_id, category_id)
);

CREATE INDEX idx_checkins_account_created_at ON checkins(account, created_at_unix);
CREATE INDEX idx_checkins_venue_id ON checkins(venue_id);
CREATE INDEX idx_raw_files_account_offset ON raw_files(account, "offset");

ALTER TABLE checkins ADD COLUMN local_timezone_id TEXT;
ALTER TABLE checkins ADD COLUMN local_timezone_offset_minutes INTEGER;
ALTER TABLE checkins ADD COLUMN local_created_at TEXT;
ALTER TABLE checkins ADD COLUMN local_date TEXT;
ALTER TABLE checkins ADD COLUMN local_hour INTEGER;
ALTER TABLE checkins ADD COLUMN local_weekday_iso INTEGER;
CREATE INDEX idx_checkins_account_local_date ON checkins(account, local_date);
CREATE INDEX idx_checkins_account_local_hour ON checkins(account, local_hour);

ALTER TABLE venues ADD COLUMN locality TEXT;
ALTER TABLE venues ADD COLUMN region TEXT;
ALTER TABLE venues ADD COLUMN postal_code TEXT;
ALTER TABLE venues ADD COLUMN country_code TEXT;
ALTER TABLE venues ADD COLUMN country TEXT;
ALTER TABLE venues ADD COLUMN neighborhood TEXT;
CREATE INDEX idx_venues_location_fields ON venues(locality, region, postal_code, country_code);

CREATE TABLE annotations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL,
    target_kind TEXT NOT NULL,
    target_id TEXT NOT NULL,
    body TEXT NOT NULL,
    source TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_annotations_account_target ON annotations(account, target_kind, target_id);
CREATE INDEX idx_annotations_account_updated_at ON annotations(account, updated_at);
CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
INSERT INTO grdb_migrations VALUES ('v1_raw_v2_import');
INSERT INTO grdb_migrations VALUES ('v2_checkin_local_time');
INSERT INTO grdb_migrations VALUES ('v3_venue_location_fields');
INSERT INTO grdb_migrations VALUES ('v4_annotations');
