# Foursquare export null-venue resolution notes

Created: 2026-04-26

This note records a behavior discovered while reconciling official Foursquare
export/takeout files with v2 API check-in detail responses.

## Summary

Some official export rows can contain `venue: null` while still preserving the
check-in id, timestamp, and coordinates. A targeted v2 check-in detail fetch can
sometimes resolve those rows back to a venue. In other cases, old check-in detail
requests may fail or return incomplete historical venue information.

## Public-safe guidance

- Treat official export rows with `venue: null` as lower-detail evidence, not as
  corrupt data.
- Preserve export-only timestamp/coordinate breadcrumbs even when venue/category
  fields are missing.
- Prefer richer v2/API rows when export rows overlap by check-in id.
- Keep per-row reconciliation artifacts, raw payloads, coordinates, filenames,
  and account-specific audit tables out of the public repo.
- If future tests need this behavior, use synthetic fixtures with fake check-in
  ids, fake coordinates, and fake venue identities.

## Implementation implications

- `db import-files` should import export-only rows without overwriting richer v2
  rows.
- `audit overlap` should summarize overlap quality without requiring raw private
  evidence in the repository.
- Any future targeted check-in-detail enrichment should write raw/private outputs
  only to ignored local data directories.
