# Intercompany reconciliation — SOX, COSO, SCF, OSCAL

Companion code for the post **[Compliance With Standards: COSO, SCF and OSCAL](https://anaivebidder.com/posts/compliance-with-standards/)**.

A US parent, an Irish manufacturing subsidiary and a German distribution
subsidiary trade with each other. Three requirements over those transactions are
written in EARS and Gherkin, bound to SCF controls, compiled to SQL, run against
the three ledgers, and emitted as NIST OSCAL `assessment-results`.

It runs at two volumes, over **the same register, the same predicates and the
same procedures**:

| Mode | Population | Purpose |
|---|---|---|
| `sample` | 7 ledger rows, 4 trades | The worked example in the post, small enough to read in full |
| `scale` | 5,000,000 trades, 9.9M legs, 5% carrying an issue | The same controls against a group-sized ledger |

Only the seed and the report differ between them. That is the point: a control
that is legible at five rows and useless at ten million is not a control.

---

## Quick start — Docker

Nothing but Docker is needed; the image installs the DuckDB CLI and nothing else.

```sh
docker compose run --rm compliance            # 5,000,000 trades
TRADES=250000 docker compose run --rm compliance
docker compose run --rm compliance sample     # the worked example
```

Or without compose:

```sh
docker build -t compliance-sox .
docker run --rm -v "$PWD/out:/work/out" -e TRADES=250000 compliance-sox scale
```

Artefacts land in `./out`.

### If the build cannot verify GitHub's certificate

The build downloads the DuckDB CLI from its official GitHub release over a
verified TLS connection. On a machine whose TLS is intercepted — a corporate
proxy, or an antivirus HTTPS scanner such as Avast Web/Mail Shield — that fails:

```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

The interceptor presents its own root for `github.com`, and the container does
not trust it. Confirm what you are being served with:

```sh
docker run --rm debian:12-slim sh -c \
  "apt-get update -qq >/dev/null && apt-get install -y -qq openssl ca-certificates >/dev/null && \
   echo | openssl s_client -connect github.com:443 -servername github.com 2>/dev/null | \
   openssl x509 -noout -issuer"
```

The right fix is to stop intercepting, or to exempt `github.com`. Failing that,
take the binary from an image that already carries it — `DUCKDB_IMAGE` replaces
the download entirely, so nothing is fetched and no certificate check is
relaxed:

```sh
docker build --build-arg DUCKDB_IMAGE=datacatering/duckdb:v1.5.5 -t compliance-sox .
```

That is a third-party image, pinned to the same version this repo was developed
against. It is an escape hatch for one machine, not a default: teaching the
image to trust an interception root would be worse, because it would travel
with the repo.

## Quick start — local DuckDB

[DuckDB](https://duckdb.org/docs/installation/) 1.0 or newer on the `PATH`; no
extensions, no network access. Developed against v1.5.5.

```sh
./run.sh sample
TRADES=250000 ./run.sh scale
```

Or drive the SQL directly, from this directory — the entry scripts use
`.read sql/...` relative paths:

```sh
duckdb < intercompany-validation.sql
{ echo "SET VARIABLE trade_count = 250000;"; cat intercompany-at-scale.sql; } | duckdb scale.db
```

A file-backed database is strongly preferred for `scale`; in memory, 5,000,000
trades will ask for most of a laptop.

---

## What comes out

| Artefact | Mode | What it is |
|---|---|---|
| `oscal-assessment-results.json` | both | One observation per exception, one finding per control, each traced to its requirement and to SOX §404(a); OSCAL 1.1.2 |
| `exceptions-req-301.csv` | `scale` | Every unmatched or out-of-tolerance trade, largest first |

Measured at 5,000,000 trades on a 2026 laptop, with the split the run prints
for itself (`===SCALE=== 9. where the time went`):

| Phase | Seconds |
|---|---|
| Build the population | ~34 |
| Run every control | ~5 |
| Report and emit evidence | ~1 |
| **Check and emit, no build** | **~6** |

Building the population is scaffolding and happens once; checking it is the
part that recurs at every period end, and that is 6 seconds over 9.9M legs.
~780 MB database, 14 MB exception report, 190,002 exception rows.

---

## The four layers

| Layer | Standard | In the script |
|---|---|---|
| 1 . Regulation | SOX §404(a), §404(b) | `Mandate` — section and subsection as separate columns |
| 2 . Governance | COSO principles 10, 11, 13 | `Requirement`, `RequirementGovernance` — carries the `mandateId` it discharges |
| 3 . Controls | SCF catalog | `ControlCatalog`, `Profile`, `Control` |
| 4 . Evidence | OSCAL `assessment-results` | `Observation`, `Finding`, the exported JSON |

## The three requirements

| Requirement | SCF control | What it asks |
|---|---|---|
| `REQ-301` | `ORG-DCH-01` Intercompany Matching & Validation | Reject unless both legs are recorded, both are translated, and the two agree within 1 USD |
| `REQ-302` | `HRS-11` Separation of Duties | Refuse unless both posting identities are recorded and they differ |
| `REQ-303` | `MON-03.2` Audit Trails | Reject unless the leg carries rate, source and timestamp |

Each has two controls: an EARS sentence (`-C1`) and a Gherkin scenario (`-C2`).

The EARS sentences use the **unwanted-behaviour** template — `IF <any condition
fails>, THEN the service SHALL reject` — so they **fail closed**. Each one lists
everything that must hold, negated and joined by `OR`; any single term rejects.

Each sentence compiles to one predicate, defined once (`ic_rejected`,
`sod_refused`, `fx_rejected`) and shared by the EARS invariant and the Gherkin
assertion, so the sentence and the check cannot drift apart. The `IS NULL` terms
in those predicates are what makes them strict: an absent value is not a passing
value.

`ORG-DCH-01` is organization-defined. Intercompany matching is a financial
reporting control and the SCF catalog does not carry one, so it is prefixed
`ORG-` rather than dressed up as an SCF identifier.

---

## The generated population

5% of trades carry an issue. The split is deterministic — `bucket = i % 1000` —
so a given volume always produces the same population, and the counts are exact
rather than sampled.

| Cause | Share | At 5,000,000 trades | Caught by |
|---|---|---|---|
| The buyer never records its leg | 2.0% | 100,000 | `REQ-301` |
| The buyer records a smaller amount (timing) | 1.8% | 90,000 | `REQ-301` |
| One identity posts both legs | 0.7% | 35,000 | `REQ-302` |
| The leg carries no translation record | 0.5% | 25,000 | `REQ-303` |

Plus the four named exemplars from the post — `IC-1001` clean, `IC-1002`
missing its buyer leg, `IC-1003` 60K apart, `IC-1004` reconciled but missing
its rate timestamp — loaded first so the Gherkin scenarios still have the
references they name by hand.

At 5,000,000 trades that is **250,002 exceptions against 58.61B of unmatched
receivable**, and all three requirements come back `FAIL`:

| reqId | COSO | controls | satisfied | failed | status |
|---|---|---|---|---|---|
| REQ-301 | 13 | 2 | 1 | 1 | FAIL |
| REQ-302 | 10 | 2 | 1 | 1 | FAIL |
| REQ-303 | 11 | 2 | 0 | 2 | FAIL |

At seven rows `REQ-301` and `REQ-303` fail and `REQ-302` holds, which is the
version the post walks through.

---

## Schema

```
Mandate(mandateId, authority, section, subsection, obligation)

Requirement(reqId, description, importance, validationProcedure)
    ├─< RequirementGovernance(reqId, mandateId, cosoComponent, cosoPrinciple, principleText)
    │       └─> Mandate
    └─< Control(controlId, reqId, scfId, methodology, description)
            ├─> ControlCatalog(scfId, domain, name, source)
            └─< StoredProcedures(procedureName, controlId)

Ex301, Ex302, Ex303        -- the materialised exception reports
Sc301, Sc302, Sc303        -- the materialised scenario verdicts
AssessmentRun              -- one row per control: state and detail
Observation(uuid, collected, method, type, controlId, description, evidenceHref)
Finding(uuid, controlId, targetType, targetId, state, reason, title)
ExceptionRow, FindingObservation  -- the evidence, shaped for the export

Entity(entityId, name, country, currency, ledgerTable)

LedgerUsParent(entryId, icRefId, counterpartyId, leg, postingDate,
               amountLocal, currency, fxRate, fxSource, fxAsOf, amountUsd,
               glAccount, postedBy)
LedgerIeMfg(... same shape ...)
LedgerDeDist(... same shape ...)

IcLedgerEntry  -- VIEW: the three ledgers unioned, entity named here
```

The top half is the register; the bottom half is ordinary operational data.

Each entity keeps its own ledger, in its own table, in its own functional
currency — there is no `entityId` column because the table *is* the entity.
Each row is one posted **leg**: `AR` for a sale to the counterparty, `AP` for a
purchase from it. A transaction is the pair — one row in each company's table —
and nothing links them but a shared `icRefId`. The `IcLedgerEntry` view unions
the three for consolidation, and is the only place an entity is named.

That is exactly why a missing row is invisible until something looks for it:
`IC-1002` is absent from `LedgerDeDist`, and no query against the German
ledger alone can see a row that was never posted.

Every control traces up an unbroken chain: `Control.scfId` to the catalog,
`Control.reqId` to a requirement, `RequirementGovernance` to a COSO principle
and to `Mandate.mandateId` — which resolves to an authority, a section and a
subsection. `SOX-404b` deliberately has no requirements against it: attestation
is the auditor's obligation, not one the group's controls discharge.

Every observation and every finding carries the register above it. `props`
name the control, the requirement, the COSO component and principle, and the
statute subsection; `links` point into `back-matter`, which defines each
requirement and each SOX subsection as a resource. The chain SOX 404(a) → COSO
principle → SCF control → transaction therefore travels *with* the evidence
rather than staying behind in the database.

Resource UUIDs come from `uuid_of()`, an md5 of the register identifier laid
out as a v4 UUID, so `REQ-301` and `SOX-404a` keep the same UUID between runs
and two quarters' documents diff cleanly.

Observations are written **one per exception**, not one per control: a control
that failed on two references produces two observations, each with its own
description and an evidence href naming the procedure and the reference that
raised it (`sql://procedure/check_req_301#IC-1002`). The finding stays single —
the control either holds or it does not — and lists them all in
`related-observations`.

At group volume that would be six figures of observations in a document meant to
be read, so each control contributes at most `observation_cap` of them, largest
variance first; the full population stays in the CSV. Override it the way the
trade count is overridden:

```sh
SET VARIABLE observation_cap = 50;
```

Each procedure runs **once** and its output is materialised into `Ex30x` /
`Sc30x`. At group volume the invariants aggregate ten million legs, and calling
them once per column of a report is the difference between seconds and minutes.
It is also what an auditor wants: the exception report, kept, not recomputed.

---

## Files

| File | What it is |
|---|---|
| [`run.sh`](run.sh) | Entry point. `sample` or `scale`, reads `TRADES`, `OUT`, `KEEP_DB`. |
| [`Dockerfile`](Dockerfile) | Debian slim plus the DuckDB CLI. Nothing else. |
| [`docker-compose.yml`](docker-compose.yml) | Mounts `./out` and passes `TRADES`. |
| [`intercompany-validation.sql`](intercompany-validation.sql) | The worked example: modules, the five-row seed, the post's report. |
| [`intercompany-at-scale.sql`](intercompany-at-scale.sql) | The same modules, the generator, the group-sized report. |
| [`sql/01-register.sql`](sql/01-register.sql) | Layers 1-4 of the register. No operational data. |
| [`sql/02-ledgers.sql`](sql/02-ledgers.sql) | The three ledger tables and the consolidation view. |
| [`sql/03-checks.sql`](sql/03-checks.sql) | `money()`, the rejection predicates, and the twelve procedures. |
| [`sql/04-run.sql`](sql/04-run.sql) | Materialises the exceptions, then the assessment, observations and findings. |
| [`sql/seed-sample.sql`](sql/seed-sample.sql) | The seven rows from the post. |
| [`sql/seed-scale.sql`](sql/seed-scale.sql) | The generator. |
| [`sql/report-sample.sql`](sql/report-sample.sql) | The seven tables the post prints. |
| [`sql/report-scale.sql`](sql/report-scale.sql) | The group-sized summary, plus the exception CSV. |
| [`sql/oscal-export.sql`](sql/oscal-export.sql) | The OSCAL document. Shared by both reports. |

`out/`, `*.db` and the generated artefacts are git-ignored.

---

## A note on the data

`Northwind Holdings`, the three entities, the posting identities and every
amount are fictional. The seven-row example is sized to make each failure visible
in as few rows as possible; the generated population is sized to show that the
same three questions survive a real ledger.

Generated breaks are amount differences — the buyer books 96% of what the seller
invoiced, the way a partial receipt or a period-end cut-off arrives in practice.
The FX-rate story, where the two sides translate at 1.25 and 1.20, stays in the
named exemplar `IC-1003`.
