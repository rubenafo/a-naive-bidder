-- =====================================================================
-- The result tables the post prints, at worked-example size.
-- =====================================================================

.print ===POST=== 1. the register read top down: SOX to COSO to SCF
SELECT m.authority, m.section, m.subsection,
       g.cosoComponent, g.cosoPrinciple AS principle,
       r.reqId, c.scfId, cc.name AS scf_control, count(*) AS controls
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId     = r.reqId
  JOIN Mandate m               ON m.mandateId = g.mandateId
  JOIN Control c               ON c.reqId     = r.reqId
  JOIN ControlCatalog cc       ON cc.scfId    = c.scfId
 GROUP BY ALL ORDER BY r.reqId, c.scfId;

.print ===POST=== 2. the unmatched legs
SELECT icRefId, seller, buyer, money(ar_usd) AS ar_usd, money(ap_usd) AS ap_usd,
       money(variance_usd) AS variance_usd, reason
  FROM Ex301 ORDER BY icRefId;

.print ===POST=== 3. the controls, one verdict each
SELECT a.controlId, c.methodology, c.scfId, a.state, a.detail
  FROM AssessmentRun a JOIN Control c ON c.controlId = a.controlId
 ORDER BY a.controlId;

.print ===POST=== 4. SOX 404 roll-up by COSO principle
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

.print ===POST=== 5. conclusion: every SOX requirement, its controls and their results
SELECT r.reqId, g.cosoPrinciple AS coso, c.scfId, c.controlId, c.methodology,
       a.state AS control_result,
       CASE WHEN count(*) FILTER (WHERE a.state = 'not-satisfied')
                 OVER (PARTITION BY r.reqId) > 0
            THEN 'FAIL' ELSE 'PASS' END AS requirement_verdict
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId = r.reqId
  JOIN Control c               ON c.reqId = r.reqId
  JOIN AssessmentRun a          ON a.controlId = c.controlId
 ORDER BY c.controlId;

.print ===POST=== 6. requirement status: how many controls, how many held
SELECT r.reqId, g.cosoComponent, g.cosoPrinciple AS coso,
       count(*) AS controls,
       count(*) FILTER (WHERE a.state = 'satisfied')     AS satisfied,
       count(*) FILTER (WHERE a.state = 'not-satisfied') AS failed,
       CASE WHEN count(*) FILTER (WHERE a.state = 'not-satisfied') > 0
            THEN 'FAIL' ELSE 'PASS' END AS status
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId = r.reqId
  JOIN Control c               ON c.reqId = r.reqId
  JOIN AssessmentRun a          ON a.controlId = c.controlId
 GROUP BY ALL ORDER BY r.reqId;

.read sql/oscal-export.sql

.print ===POST=== 7. wrote oscal-assessment-results.json
