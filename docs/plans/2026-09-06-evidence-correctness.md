# Evidence correctness and architecture plan

Date: 2026-09-06
Baseline: `90c8c09`, v0.7.0
Status: implemented and verified, 2026-09-06. Deployment remains separate.

## Implementation outcome

- Five slices implemented with no added third-party dependencies.
- Account-keyed config, immutable source artifacts/shared validators, persisted
  sync/coverage state, typed selection/comparison windows, and invocation-owned
  CLI dependencies are now the active paths.
- v5/v6 migrations preserve legacy IDs and annotations; legacy provenance remains
  unverified. No automatic legacy repair or production migration was performed.
- Comparison JSON uses schema version 2; existing drill_down is the baseline alias,
  with explicit baseline/recent descriptors and baseline metric scope.
- Verification: swift build and 123 tests, including same-second freshness,
  disjoint-window support, nested command execution, and migration rollback.
- Detailed operational contracts are in docs/operations-and-query-semantics.md.
- Deferred items remain in TODO.md. The scope and acceptance criteria below are
  retained as the implementation record.

## Scope

Address review findings P1 #1 (credential/account collisions), P1 #2
(comparison windows), P1 #3 (export provenance), and #9 (no-new-data freshness).
Use the first four proposed refactoring boundaries to make those fixes durable:

1. Typed query filters and windows shared by summaries and drill-downs.
2. Account-scoped source/provenance handling shared by ingest, import, and audit.
3. Explicit recent-sync versus historical-coverage state.
4. CLI infrastructure separated from core logic, without global invocation state.

The shared query boundary also resolves #7 (end-date handling) and #8
(category-filtered drill-downs). Shared source validation resolves #4
(audit account scope). These are direct consequences of the requested boundaries,
not separate feature projects.

Masked auth input (#5), general category reconciliation (#6), annotation
backup/export architecture, trip clustering, and other feature work remain out of
scope. Preserve annotations through all migrations. No install, live account
probe, production-data migration, commit, or push is part of this planning task.

## Approach and dependency order

Keep Swift, GRDB, explicit SQL, and swift-argument-parser. The existing GRDB
migrator/transactions and ArgumentParser's parseAsRoot seam cover the needed
capabilities; no new framework, ORM, DI container, or general query builder.

Implement five independently reviewable slices in this order:

`account resolution -> provenance -> sync state -> query contracts -> CLI split`

Each slice adds focused failing regressions first, implements the boundary, and
finishes with passing checks. Do not mix mechanical file moves with SQL/schema
changes. The query slice is logically independent of provenance, but comes after
it in the default serial execution order.

## 1. Exact account resolution and typed configuration

Primary files: SourceProbe.swift, SetupAuth.swift, SourceStatus.swift,
SwarmCadenceCommand.swift; new focused configuration/account files.

- Introduce exact AccountID and account-keyed configuration values. JSON account
  dictionaries must never be flattened into normalized environment keys.
- Resolve the selected account once. Pass only its resolved credentials and
  paths to source operations; keep secret-bearing values out of renderable DTOs.
- Preserve existing JSON shape and precedence for unambiguous configurations.
  Centralize placeholder handling rather than maintaining copies in each caller.
- Isolate legacy dotenv/flat/environment inputs behind one adapter. Reject
  ambiguous mappings before any network or database write. Do not silently choose
  between a-b/a_b or case variants. A noncanonical label without an exact JSON
  binding must not inherit a canonical label's ambient credential.
- Preserve supported existing simple labels; do not rename accounts or relocate
  their directories as part of the fix.

Acceptance:

- a-b and a_b have distinct JSON credentials; an unconfigured sibling cannot
  borrow the other's token. Include case variants and one-account configurations.
- Ambiguous legacy/env overrides fail deterministically, without printing values.
- Auth status, source status/probe, raw fetch, and ingest agree on resolution.
- Existing ordinary single-/multi-account behavior and config merging remain valid.

## 2. Immutable, account-scoped source provenance

Primary files: DatabaseImport.swift, RawFetch.swift, SourceAudit.swift;
new source-artifact validation/storage files and GRDB migration.

- Separate immutable source content identity from observations of that content.
  Content identity includes exact account, adapter, and SHA256. A basename is a
  locator, never a unique artifact identity. Retain each observation's original
  filename/location, collection metadata, and fetch/import times separately.
- Repeating identical input is idempotent for normalized evidence. Different
  content under checkins1.json creates distinct provenance; a later import must
  never rewrite metadata referenced by earlier check-ins.
- Provide one validated source-reader boundary: account, adapter/schema, payload
  shape, manifest size/hash when available, and source observation metadata.
  Import and audit consume this boundary. Export account attribution remains an
  explicit caller assertion, since an export may lack verifiable account metadata.
- Preserve the current API-over-export precedence. Reject conflicting ownership
  of a check-in rather than reassigning its account on upsert.
- Keep normalization and its provenance references transactionally consistent.

Migration:

- Preserve check-in, category, annotation, and existing referenced raw-file IDs;
  allow legacy references alongside the new identity model during migration.
- Do not infer missing original hashes/accounts after historical overwrites.
  Mark legacy provenance unverified unless it can be checked against supplied raw
  files. Do not manufacture a trustworthy history from current DB rows.
- Test migration with an old-schema fixture, including deliberately corrupted
  cross-account provenance. Recovery/reindexing from actual archives is a separate,
  explicit operation; never automatically wipe/rebuild a live database.

Acceptance:

- Same filename in two snapshots, in two accounts, and after archive relocation.
- Identical reimport does not duplicate normalized visits.
- Earlier source references remain unchanged after later imports.
- Wrong-account, missing-raw, bad-hash, and malformed sources cannot become valid
  audit evidence. Rejections identify files/reasons without credential payloads.
- Migration rollback preserves the pre-migration state and annotation rows.

## 3. Honest freshness and historical coverage

Primary files: IngestUpdate.swift, DatabaseImport.swift freshness helpers,
RawFetch.swift, query/evidence freshness DTOs; new sync-state migration.

- Persist account/adapter-scoped ingestion runs and successful source observations,
  independently of whether normalized check-ins were newly inserted.
- Distinguish last source check, last import, newest observed check-in, recent-sync
  completion, and historical coverage. Keep last attempt/failure separate from
  last successful check; offline replay is not a fresh network check.
- Validate and record an all-known-ID page before stopping. Advance fetch/check
  freshness without changing visit counts. Do not force normalized metadata
  rewrites merely to advance a timestamp; complete category reconciliation remains
  deferred, and no-new-data status must not promise metadata reconciliation.
- Treat complete as an invocation/recent-sync concept, not an archive-completeness
  claim. Add explicit history coverage: unknown, partial, or verified as of a
  recorded traversal. Preserve/clearly label the old field for existing consumers
  until an intentional schema transition; do not silently redefine it.
- A capped/failed traversal stays partial after a later all-known head page.
  Only a validated full traversal with accounted-for pages can establish historical
  coverage, scoped to its observation time and offset-pagination limitations.
  Counts or min/max timestamps alone cannot establish completeness.
- Record offsets/cursors as diagnostic continuation hints, not permanent positions
  in a changing remote feed. Keep collection bounded. Do not add a new automatic
  full-backfill engine in this slice; existing raw collection remains explicit.
- Surface malformed/skipped-page import as a failure or partial result, never as
  a successfully imported page or proof of coverage.

Acceptance:

- Successful all-known page advances source-check/fetch freshness, inserts zero
  visits, and preserves the semantics of last-imported time.
- A failed request cannot advance last-success time; offline replay cannot either.
- Capped first run with two of three remote rows remains historically partial
  after the next run reaches known IDs.
- Empty account/full traversal, mixed overlap, malformed page, and interruption
  produce explicit, truthful state. State cannot cross account boundaries.
- Use injected clocks and mock transports; update the existing test that currently
  enshrines skipping the no-new-data observation.

## 4. Typed evidence filters and independent comparison windows

Primary files: DatabaseQuery.swift, EvidenceBundle.swift, Geography.swift,
query option parsing and renderers in SwarmCadenceCommand.swift.

- Introduce small value types for date bounds/windows, local-calendar filters,
  category/geography selection, and comparison windows. Keep sort/limit separate
  from evidence membership. Avoid one optional-field-heavy universal options type.
- Normalize date-only upper bounds consistently for --to, --baseline-to, and
  --recent-to. Preserve explicit-instant semantics and the distinction between
  UTC date bounds and visit-local --date filters. Validate impossible dates.
- Select the candidate venue set from baseline support (preserve min-baseline-
  visits behavior), then calculate baseline and recent aggregates independently
  using the same non-window filters. Recent-only venues remain outside that set.
- Support disjoint, nested, and overlapping windows without clipping recent rows
  to baseline bounds. Define previous support as baseline rows before recent start,
  not baseline minus recent, which is invalid for some window arrangements.
- Explicitly scope first/last timestamps, gaps, and days-since calculations in the
  result contract. Expose window-specific fields where a single value would be
  misleading; review/version affected JSON rather than silently changing meanings.
- Build summary queries and visit drill-downs from the same normalized filter.
  Add category selection to query visits so the emitted command can actually
  reproduce category-filtered support. Comparisons need distinct baseline/recent
  drill-downs. Carry limits/truncation indicators honestly.
- Route venues, visits, cadence, compare, lapses, and experimental envelopes through
  these shared contracts. Keep SQL explicit and parameterized.

Acceptance:

- One 2024 visit and one 2025 visit yield baseline=1/recent=1 for disjoint years.
- Nested/overlapping windows, gaps, empty recent windows, min support, and sorting.
- Noon on an end date is included; the following day is excluded.
- Executing each drill-down reproduces the scoped support IDs/count, accounting
  explicitly for output limits. Exercise categories, local hours, and named areas.
- Compare and lapses share semantics; evidence envelopes do not fork the logic.

## 5. Thin CLI and invocation-owned dependencies

Primary files: Package.swift, SwarmCadenceCommand.swift, CLI/main.swift, tests.

- Keep SwarmCadenceCore responsible for domain/config/source/storage/query services,
  with no ArgumentParser dependency. Add a small SwarmCadenceCommands target for
  parsing, command execution, and text/JSON presentation; keep main.swift minimal.
- Retain the testable run(arguments:..., dependencies:...) seam in the commands
  target. Inventory repo consumers before moving it; update tests explicitly rather
  than retaining a second implementation in Core.
- Replace CommandRuntime.current with an invocation-owned context containing
  environment, transport, clock, input, and output. Parse using parseAsRoot, then
  dispatch parsed commands through an explicit execute(context:) seam. No globals,
  task-local singleton, or implicit cross-invocation dependency lookup.
- Split command families, output rendering, and configuration adapters into focused
  files. Move code only after behavior is fixed, preserving help and error behavior.

Acceptance:

- Core builds without ArgumentParser. Success, validation failures, --help,
  --version, signed arguments, noninteractive mode, JSON, and text remain covered.
- Two overlapping/reentrant invocations with separate contexts cannot mix accounts,
  transport responses, output, or exit codes. Use separate temp DBs for this test.
- No new dependencies; no CLI or installed-skill changes merely for file organization.

## Verification and completion

- Use synthetic fixtures, mock HTTP transports, injected clocks, and explicit
  temporary config/raw/database paths throughout.
- Run focused regressions per slice, then swift build and swift test after the
  integrated changes. Baseline evidence: 107 tests passed during the review; this
  planning task does not claim a new test run.
- Inspect representative human-readable CLI success/error output and machine JSON.
- Update operations/query semantics, focused architecture guidance in AGENTS.md,
  and TODO.md with the final contracts. Keep README changes limited to user-visible
  behavior. Document remaining deferred findings without marking them solved.
- Test schema upgrades and failure/rollback paths without losing annotations or
  pretending damaged legacy provenance has been recovered.
- Code completion means all scoped regressions pass and migrations/contracts are
  reviewable. Deployment, installed skill refresh, and live-data reconciliation
  remain separate actions, not hidden consequences of implementing this plan.
