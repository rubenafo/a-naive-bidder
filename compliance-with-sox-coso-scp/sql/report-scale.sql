-- =====================================================================
-- The same assessment, reported at group volume.
--
-- Nothing here prints a row per exception: at 5,000,000 trades the
-- exception report is a quarter of a million lines. It is kept in Ex301,
-- Ex302 and Ex303 and summarised below - which is how a reconciliation is
-- actually worked: totals first, then the population you have to clear.
-- =====================================================================

.print ===SCALE=== 1. the population
SELECT (SELECT count(*) FROM LedgerUsParent) AS us_parent_legs,
       (SELECT count(*) FROM LedgerIeMfg)    AS ie_mfg_legs,
       (SELECT count(*) FROM LedgerDeDist)   AS de_dist_legs,
       (SELECT count(*) FROM IcLedgerEntry)  AS total_legs,
       (SELECT count(DISTINCT icRefId) FROM IcLedgerEntry) AS trades;

.print ===SCALE=== 2. the register read top down: SOX to COSO to SCF
SELECT m.authority, m.section, m.subsection,
       g.cosoComponent, g.cosoPrinciple AS principle,
       r.reqId, c.scfId, count(*) AS controls
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId     = r.reqId
  JOIN Mandate m               ON m.mandateId = g.mandateId
  JOIN Control c               ON c.reqId     = r.reqId
 GROUP BY ALL ORDER BY r.reqId;

.print ===SCALE=== 3. the exception population, by cause
SELECT reason,
       count(*)                     AS trades,
       money(sum(abs(variance_usd))) AS gross_variance_usd,
       money(max(abs(variance_usd))) AS largest_single,
       round(100.0 * count(*) /
             (SELECT count(DISTINCT icRefId) FROM IcLedgerEntry), 3) AS pct_of_trades
  FROM Ex301 GROUP BY reason
 UNION ALL
SELECT reason, count(*), NULL, NULL,
       round(100.0 * count(*) /
             (SELECT count(DISTINCT icRefId) FROM IcLedgerEntry), 3)
  FROM Ex302 GROUP BY reason
 UNION ALL
SELECT reason, count(*), NULL, NULL,
       round(100.0 * count(*) /
             (SELECT count(DISTINCT icRefId) FROM IcLedgerEntry), 3)
  FROM Ex303 GROUP BY reason
 ORDER BY trades DESC;

.print ===SCALE=== 4. the ten largest unmatched trades
SELECT icRefId, seller, buyer, money(ar_usd) AS ar_usd, money(ap_usd) AS ap_usd,
       money(variance_usd) AS variance_usd, reason
  FROM Ex301 ORDER BY abs(variance_usd) DESC, icRefId LIMIT 10;

.print ===SCALE=== 5. unmatched exposure by entity pair
SELECT seller, buyer, count(*) AS trades, money(sum(abs(variance_usd))) AS gross_variance_usd
  FROM Ex301 GROUP BY seller, buyer ORDER BY sum(abs(variance_usd)) DESC;

.print ===SCALE=== 6. the controls, one verdict each
SELECT a.controlId, c.methodology, c.scfId, a.state, a.detail
  FROM AssessmentRun a JOIN Control c ON c.controlId = a.controlId
 ORDER BY a.controlId;

.print ===SCALE=== 7. SOX 404 roll-up by COSO principle
SELECT g.cosoComponent, g.cosoPrinciple AS principle,
       count(DISTINCT c.controlId) AS controls,
       count(DISTINCT CASE WHEN f.state = 'not-satisfied' THEN c.controlId END) AS not_satisfied,
       CASE WHEN count(DISTINCT CASE WHEN f.state = 'not-satisfied' THEN c.controlId END) > 0
            THEN 'DEFICIENCY' ELSE 'effective' END AS conclusion
  FROM RequirementGovernance g
  JOIN Mandate m     ON m.mandateId = g.mandateId
  JOIN Control c     ON c.reqId = g.reqId
  JOIN Finding f     ON f.controlId = c.controlId
 WHERE m.authority = 'SOX' AND m.section = '404'
 GROUP BY ALL ORDER BY g.cosoPrinciple;

.print ===SCALE=== 8. requirement status: how many controls, how many held
SELECT r.reqId, g.cosoComponent, g.cosoPrinciple AS coso,
       count(*) AS controls,
       count(*) FILTER (WHERE a.state = 'satisfied')     AS satisfied,
       count(*) FILTER (WHERE a.state = 'not-satisfied') AS failed,
       CASE WHEN count(*) FILTER (WHERE a.state = 'not-satisfied') > 0
            THEN 'FAIL' ELSE 'PASS' END AS status
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId = r.reqId
  JOIN Control c               ON c.reqId = r.reqId
  JOIN AssessmentRun a         ON a.controlId = c.controlId
 GROUP BY ALL ORDER BY r.reqId;

-- The exception report is evidence: it is written out beside the OSCAL
-- document rather than left in memory.
COPY (SELECT icRefId, seller, buyer, ar_usd, ap_usd, variance_usd, reason
        FROM Ex301 ORDER BY abs(variance_usd) DESC, icRefId)
  TO 'exceptions-req-301.csv' (HEADER, DELIMITER ',');

.read sql/oscal-export.sql

INSERT INTO RunPhase VALUES ('reported', get_current_timestamp());

.print ===SCALE=== 9. where the time went
SELECT phase, round(secs, 1) AS seconds FROM (
            SELECT 'build the population' AS phase, 1 AS ord,
                   epoch((SELECT max(markedAt) FROM RunPhase WHERE phase='seeded')
                       - (SELECT max(markedAt) FROM RunPhase WHERE phase='start')) AS secs
  UNION ALL SELECT 'run every control', 2,
                   epoch((SELECT max(markedAt) FROM RunPhase WHERE phase='checked')
                       - (SELECT max(markedAt) FROM RunPhase WHERE phase='seeded'))
  UNION ALL SELECT 'report and emit evidence', 3,
                   epoch((SELECT max(markedAt) FROM RunPhase WHERE phase='reported')
                       - (SELECT max(markedAt) FROM RunPhase WHERE phase='checked'))
  UNION ALL SELECT 'check and emit (no build)', 4,
                   epoch((SELECT max(markedAt) FROM RunPhase WHERE phase='reported')
                       - (SELECT max(markedAt) FROM RunPhase WHERE phase='seeded'))
) ORDER BY ord;

.print ===SCALE=== 10. wrote oscal-assessment-results.json and exceptions-req-301.csv
