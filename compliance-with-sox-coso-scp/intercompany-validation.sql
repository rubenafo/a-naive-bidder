-- =====================================================================
-- Compliance With Standards: SOX, COSO, SCF and OSCAL
-- The worked example from the post: five ledger rows, three requirements,
-- six controls, one OSCAL assessment-results document.
--
--   duckdb < intercompany-validation.sql          # in-memory, repeatable
--   duckdb intercompany.db < intercompany-validation.sql   # keep it
--
-- Runs on DuckDB 1.0+. No extensions, no network access. Must be run from
-- this directory: the .read paths below are relative to it.
--
-- Writes oscal-assessment-results.json into the current directory.
--
-- The same four modules run the group-sized population; only the seed and
-- the report differ. See intercompany-at-scale.sql.
-- =====================================================================

.read sql/01-register.sql
.read sql/02-ledgers.sql
.read sql/03-checks.sql
.read sql/seed-sample.sql
.read sql/04-run.sql
.read sql/report-sample.sql
