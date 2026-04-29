# Pattern Boundary and Corrections — swarm-cadence

This note turns the broader OpenClaw pattern-intelligence work into concrete guidance for `swarm-cadence`.

Related Obsidian annotations:
- `LLM Pattern Loop`
- `Pattern Extraction Tooling`
- `Personal Pattern Intelligence`
- `Almanacs and Guides`

Related repo annotations:
- `docs/pattern-intelligence-proposal.md`
- `docs/source-probe-setup.md`

## Boundary

`swarm-cadence` is the place/visit evidence instrument, not the lunch recommender or life narrator.

The useful layering is:

```text
Swarm/Foursquare raw responses and exports
  -> normalized check-ins / venues / categories / geography
  -> stable query verbs and descriptive cadence/lapse/identity observations
  -> Robut-composed Lunch Guide / Place Almanac / profile reflection
  -> human correction or policy where needed
```

Datasette/read-only SQL is the microscope for source coverage and debugging. CLI verbs are domain-shaped instruments. Robut composes the Guide.

The lunch acceptance test is useful, but it must not harden into a tool-owned lunch recommender.

## What belongs in `swarm-cadence`

Good tool-layer work:

- source/account readiness and ingest freshness;
- raw/source overlap and identity audit;
- visits, venues, categories, cadence, compare, lapses, and trips over explicit windows/geography/category filters;
- named geography as transparent query expansion, with resolved primitives shown;
- descriptive active/lapsed evidence with support counts, first/last seen, gaps, and drill-downs;
- category groups only if explicit, named, inspectable, and expanded in output;
- travel-burst clustering as bounded descriptive grouping;
- approved correction application only after correction semantics are explicit and human-authorized.

## What stays above `swarm-cadence`

Do not make the CLI decide:

- where Julian should eat today;
- whether a venue is a favorite, convenience artifact, identity-significant, or socially meaningful;
- current open-now suitability unless joined with a separate current source;
- cross-domain joins with Paprika, clime, calendar, family context, or messages;
- polished Lunch Guide / Place Almanac prose;
- durable preference/profile changes without human approval.

Those are Robut/Guide-layer judgments over explicit visit/place evidence.

## Human-attached annotations, not correction machinery

Near-term correction handling should be simple: a human attaches a annotation to the thing Robut is likely to encounter again. The note supplies context; the LLM decides how to use it next time.

The hard part is not schema. The hard part is **what object the note attaches to** and **where Robut will reliably find it later**.

Useful attachment targets for `swarm-cadence`:

- a venue, for “convenience not preference,” “still liked,” closed/renamed, or not-for-context notes;
- a check-in or visit window, for travel/social obligation/one-off context;
- a category/group, for bad metadata or household meaning;
- a geography/anchor/area, for local-vs-travel interpretation;
- a person/family context, for Julian/Alice/shared distinction.

Example annotations:

- Venue body: “Went here often because it was near work, not because it was a favorite.”
- Venue body: “Still a good lunch option; absence is because the office moved.”
- Visit-window body: “Hong Kong check-ins are travel context; don’t mix with local lunch habits.”
- Category body: “This venue’s Foursquare category is misleading.”

Store the note somewhere human-readable first: Obsidian, profile memory, or a small sidecar only when retrieval needs it. Raw check-ins stay immutable. Do not require humans to choose correction kinds, approval states, or future effects.

If this later becomes machine-readable, keep the durable shape minimal:

```text
attached_to: <kind:id>
body: <plain English human note>
source: <human/chat/note>
updated_at: <timestamp>
```

Supported attachment kinds are deliberately small: `venue`, `checkin`, `category`, `geography`, `context`, and `window`. Target IDs stay flexible; `geography:burlingame-lunch-radius` and `context:local-lunch` are valid when the useful handle is human-shaped rather than a source row id.

That is enough for Robut to find the note and reason from it.

## Actionable next slices

1. **OpenClaw skill**
   - Document safe query/ingest use, category selection, freshness, and how Robut should turn source pieces into Guide language.

2. **Attached-note examples**
   - Add examples of annotations attached to venues, check-ins/windows, categories, geography, and person/family contexts.
   - Decide where Robut will reliably find those notes later: Obsidian/profile memory first, sidecar only if needed.

3. **Trip/travel-burst clustering**
   - Add descriptive trip clusters so travel/airport/hotel bursts do not pollute ordinary local Guide reasoning.
   - Keep this as dates, geography, support, top venues/categories, and drill-downs.

4. **Category group contract only if exact categories remain too repetitive**
   - Saved groups must expand to concrete Foursquare categories in output.
   - Do not add fuzzy cuisine/preference models in the CLI.

5. **Retire or demote experimental evidence envelopes**
   - Keep stable contracts as smaller source/derived pieces.
   - Do not make `swarm-cadence` own the final evidence packet or Guide packet.
