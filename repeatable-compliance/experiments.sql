-- =====================================================================
-- Experiments: change the data, watch the controls respond.
--
--   duckdb < requirements-validation.sql > /dev/null   # (sanity check)
--   cat requirements-validation.sql experiments.sql | duckdb
--
-- A control you have only ever seen pass, or only ever seen fail, has not
-- been tested. Each experiment below perturbs the operational data and
-- shows the checks reacting, then puts the data back.
-- =====================================================================

.print
.print ### 1. The Gherkin scenario follows the data, not just row existence
.print --- baseline: MEI released the transfer she initiated
SELECT (SELECT count(*) FROM check_req_102()) AS ears_violations,
       (SELECT result FROM check_scenario_102()
         WHERE scenario = 'initiator-cannot-release-own-transfer') AS gherkin;

UPDATE TransferRelease SET released_by = 'E-01' WHERE transfer_id = 'WT-2002';
.print --- released by a DIFFERENT identity: both controls must now agree it is clean
SELECT (SELECT count(*) FROM check_req_102()) AS ears_violations,
       (SELECT result FROM check_scenario_102()
         WHERE scenario = 'initiator-cannot-release-own-transfer') AS gherkin;
UPDATE TransferRelease SET released_by = 'E-03' WHERE transfer_id = 'WT-2002';

.print
.print ### 2. "20 consecutive days" must fall inside ONE calendar year
INSERT INTO Leaves VALUES ('E-03', DATE '2026-12-20', DATE '2027-01-13');
.print --- a 25-day block over New Year is 12 days of 2026 and 13 of 2027:
.print --- it satisfies neither year, so MEI is reported in both
SELECT 2026 AS yr, name, total_leave_days, longest_consecutive_block
  FROM check_req_201(2026)
UNION ALL
SELECT 2027, name, total_leave_days, longest_consecutive_block
  FROM check_req_201(2027)
ORDER BY yr, name;
DELETE FROM Leaves WHERE startDate = DATE '2026-12-20';

.print --- and a genuine 20-day block inside one year clears the check (0 rows)
INSERT INTO Leaves VALUES ('E-03', DATE '2026-06-01', DATE '2026-06-20');
SELECT * FROM check_req_201(2026);
DELETE FROM Leaves WHERE startDate = DATE '2026-06-01';

.print
.print ### 3. Touching and overlapping periods count as one absence
INSERT INTO Leaves VALUES
  ('E-02', DATE '2026-03-01', DATE '2026-03-10'),   -- ten days
  ('E-02', DATE '2026-03-11', DATE '2026-03-20'),   -- adjacent: merges
  ('E-02', DATE '2026-03-05', DATE '2026-03-08');   -- nested: absorbed
.print --- three rows, one block, twenty days
SELECT employeeId, days FROM leave_blocks(2026) WHERE employeeId = 'E-02';
DELETE FROM Leaves WHERE employeeId = 'E-02';

.print
.print ### 4. A control that never ran must not be reported as a pass
DELETE FROM ControlResult WHERE reqId = 'REQ-102';
INSERT INTO ControlResult VALUES
  (TIMESTAMP '2026-12-31 02:00:00', 'REQ-102', 'REQ-102-C4', true, 'clean');
.print --- one control of five has evidence, and it passed: NOT a passing requirement
WITH latest AS (
  SELECT controlId, arg_max(result, timestamp) AS result FROM ControlResult
   GROUP BY controlId)
SELECT r.reqId,
       count(DISTINCT c.controlId) AS controls,
       count(DISTINCT l.controlId) AS with_evidence,
       CASE WHEN count(DISTINCT l.controlId) = 0 THEN '(no evidence)'
            WHEN NOT bool_and(l.result)            THEN 'FAIL'
            WHEN count(DISTINCT l.controlId)
                 < count(DISTINCT c.controlId)     THEN 'incomplete'
            ELSE 'pass' END AS verdict
  FROM Requirement r
  LEFT JOIN Control c ON c.reqId = r.reqId
  LEFT JOIN latest l  ON l.controlId = c.controlId
 WHERE r.reqId = 'REQ-102' GROUP BY r.reqId;

.print --- and with nothing recorded at all
DELETE FROM ControlResult WHERE reqId = 'REQ-102';
WITH latest AS (
  SELECT controlId, arg_max(result, timestamp) AS result FROM ControlResult
   GROUP BY controlId)
SELECT r.reqId,
       count(DISTINCT l.controlId) AS with_evidence,
       CASE WHEN count(DISTINCT l.controlId) = 0 THEN '(no evidence)'
            WHEN NOT bool_and(l.result)            THEN 'FAIL'
            WHEN count(DISTINCT l.controlId)
                 < count(DISTINCT c.controlId)     THEN 'incomplete'
            ELSE 'pass' END AS verdict
  FROM Requirement r
  LEFT JOIN Control c ON c.reqId = r.reqId
  LEFT JOIN latest l  ON l.controlId = c.controlId
 WHERE r.reqId = 'REQ-102' GROUP BY r.reqId;

.print
.print ### 5. Deleting a procedure is visible before anything is run
DROP MACRO check_req_201;
SELECT sp.controlId, sp.procedureName,
       CASE WHEN f.function_name IS NULL THEN 'MISSING' ELSE 'ok' END AS in_catalog
  FROM StoredProcedures sp
  LEFT JOIN duckdb_functions() f
         ON f.function_name = sp.procedureName
        AND f.function_type = 'table_macro'
 WHERE sp.controlId LIKE 'REQ-201%'
 ORDER BY sp.controlId;
.print --- C1's procedure is now missing, and nothing in the register changed to
.print --- say so: the row still names it. Only the catalog knows.
