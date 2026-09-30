-- =====================================================================
-- Compliance With Standards: the same controls at group volume.
--
--   duckdb intercompany.db < intercompany-at-scale.sql
--
-- Generates 5,000,000 intercompany trades across the three ledgers, 5% of
-- them carrying an issue, then runs the identical register, predicates and
-- procedures over them. Nothing in layers 1-4 changes: the only difference
-- between this and the five-row example is which seed loads and how the
-- result is reported.
--
-- Set the volume before running:
--   SET VARIABLE trade_count = 250000;
-- or, from the shell, TRADES=250000 ./run.sh scale
--
-- Writes oscal-assessment-results.json and exceptions-req-301.csv.
-- A file-backed database is strongly preferred over :memory: here.
-- =====================================================================

.read sql/01-register.sql
.read sql/02-ledgers.sql
.read sql/03-checks.sql
.read sql/seed-scale.sql
.read sql/04-run.sql
.read sql/report-scale.sql
