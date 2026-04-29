# Synthetic source fixtures

These files are hand-written shape fixtures for public tests and debugging. They
are not real Foursquare/Swarm data and do not contain real check-in IDs,
coordinates, tokens, account names, or venue histories.

Use them to distinguish local parser/import regressions from upstream source
shape changes. Filenames include the date when this synthetic shape was captured
or modeled, so future fixtures can preserve newer source shapes side by side:

- `FoursquareAPI/2026-04-29-users-self-checkins.json` mirrors the rough shape returned by the
  Foursquare v2 `users/self/checkins` endpoint.
- `FoursquareExport/2026-04-29-checkins1.json` mirrors the official Foursquare export file
  shape currently imported by `db import-files`.
