#!/bin/sh
# Runs the compliance example end to end.
#
#   ./run.sh sample            the five-row worked example from the post
#   ./run.sh scale             a generated population of $TRADES trades
#   TRADES=250000 ./run.sh scale
#
# Environment:
#   TRADES   trades to generate for `scale`   (default 5000000)
#   OUT      where the artefacts are left     (default ./out)
#   KEEP_DB  keep the DuckDB file afterwards  (default 1)
#
# Artefacts: oscal-assessment-results.json, and for `scale` the
# exceptions-req-301.csv exception report. Both land in $OUT.
#
# DuckDB runs from the repository root because the entry scripts use
# `.read sql/...` relative paths.
set -eu

MODE="${1:-sample}"
TRADES="${TRADES:-5000000}"
OUT="${OUT:-./out}"
KEEP_DB="${KEEP_DB:-1}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p "$OUT"
DB="$OUT/intercompany.db"
rm -f "$DB" "$DB.wal"

case "$MODE" in
  sample)
    echo "==> worked example: 5 ledger rows, 3 requirements, 6 controls"
    duckdb "$DB" < intercompany-validation.sql
    ;;
  scale)
    echo "==> generating $TRADES intercompany trades, 5% carrying an issue"
    echo "    (the database reaches roughly 160 MB per million trades)"
    start=$(date +%s)
    { echo "SET VARIABLE trade_count = $TRADES;"; cat intercompany-at-scale.sql; } \
      | duckdb "$DB"
    echo "==> completed in $(( $(date +%s) - start ))s"
    ;;
  *)
    echo "usage: $0 [sample|scale]" >&2
    exit 2
    ;;
esac

# The scripts write beside the working directory; collect what they produced.
for f in oscal-assessment-results.json exceptions-req-301.csv; do
  [ -f "$f" ] && mv -f "$f" "$OUT/"
done

[ "$KEEP_DB" = "1" ] || rm -f "$DB" "$DB.wal"

echo "==> artefacts in $OUT:"
ls -l "$OUT"
