# Source Probe Setup

This document defines the handoff between the safe local scaffolding and the
first external Foursquare/Swarm work.

The current `source probe` command is dry config validation only. It does not
call Foursquare, call Swarm, open a browser, refresh tokens, ingest check-ins,
write an evidence database, or validate whether a token/session still works.

## Current command

```bash
swift run swarm-cadence source probe --account julian --adapter v2 --format json
swift run swarm-cadence source probe --account julian --adapter historysearch --format json
```

Optional dotenv-style config:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env
```

Environment variables override values from the config file. All configured
values are reported as present or missing only; values are never printed.

## v2 OAuth path

Preferred if the future live probe can read check-in history for the account.

Current Foursquare v2 docs identify the target read endpoint as:

```text
GET https://api.foursquare.com/v2/users/self/checkins
```

The v2 docs require a version parameter and support authenticated user access
with an OAuth access token. The future live probe should test this endpoint with
a minimal limit and with redacted errors before any ingest/backfill work exists.

Required for a future live v2 probe:

```text
SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN
```

Useful setup breadcrumbs, stored outside git:

```text
SWARM_CADENCE_JULIAN_V2_CLIENT_ID
SWARM_CADENCE_JULIAN_V2_CLIENT_SECRET
SWARM_CADENCE_JULIAN_V2_REDIRECT_URI
```

Julian's external setup steps:

1. Create or identify a Foursquare developer app.
2. Register a local redirect URI for an OAuth web flow.
3. Authorize the intended account, such as `julian`.
4. Exchange the OAuth code for an access token.
5. Put the access token in the environment or in a git-ignored config file.
6. Rerun the dry probe and confirm it reports `ready_for_live_probe`.

Do not paste the token into issues, commits, test fixtures, terminal transcripts
intended for sharing, or docs.

## Swarm web historysearch fallback

Use this only if v2 OAuth is blocked, gated, or does not provide usable
check-in history.

Required for a future live historysearch probe:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN
```

Optional, only if the future live probe proves it is needed:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_COOKIE
```

Julian's external setup steps:

1. Log in to Swarm in a browser for the intended account.
2. Open the browser's network tools.
3. Find a check-in history/historysearch request.
4. Copy only the minimal request parameters needed for a future live probe:
   `userid`, `wsid`, and `oauth_token`.
5. Store those values outside git in the matching
   `SWARM_CADENCE_JULIAN_HISTORYSEARCH_*` inputs.
6. Rerun the dry probe and confirm it reports `ready_for_live_probe`.

Treat these values as browser-session secrets. They are more brittle and more
sensitive than normal app configuration.

## Account labels

The CLI requires an explicit account label:

```bash
--account julian
--account alice
```

The label becomes part of the expected variable name. Hyphens are converted to
underscores and the label is uppercased:

```text
--account julian       -> SWARM_CADENCE_JULIAN_...
--account alice        -> SWARM_CADENCE_ALICE_...
--account test-person  -> SWARM_CADENCE_TEST_PERSON_...
```

Do not use one account's token/session for another account label. Multi-account
work must preserve attribution from the first row onward.

## Next implementation checkpoint

Once Julian has supplied one adapter's required inputs locally, implement a
separate live read-only probe that:

- performs exactly one minimal network check for the selected account/adapter;
- uses explicit `--account`, `--adapter`, and `--format json`;
- redacts tokens, cookies, request ids, OAuth params, and remote account ids;
- reports field coverage for check-in ids, venue ids, timestamps, venue names,
  categories, lat/lng, photos if present, count, and date range;
- writes no default database and mutates no remote state;
- can save only sanitized fixtures when explicitly requested.

That live probe decides whether the next real slice uses v2 OAuth,
`historysearch`, or export/import bootstrap.

## References

- Foursquare v2 `Get User Checkins`: <https://docs.foursquare.com/developer/reference/get-user-checkins>
- Foursquare v2 authentication: <https://docs.foursquare.com/developer/reference/v2-authentication>
