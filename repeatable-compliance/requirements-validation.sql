-- =====================================================================
-- Towards Repeatable Compliance
-- Companion script: the complete worked example from the post.
--
--   duckdb < requirements-validation.sql          # in-memory, repeatable
--   duckdb requirements.db < requirements-validation.sql   # keep it to explore
--
-- Runs on DuckDB 1.0+. Creates the requirements register, the operational
-- tables and every control procedure, then reproduces each result table
-- printed in the post, in the order the post prints them.
--
-- The second form needs a database file that does not exist yet: the script
-- creates its tables rather than replacing them, so re-running it over a
-- database it already populated is a catalog error, not a reset.
-- =====================================================================

-- ===== the register: one row per Requirement, plain text =============
CREATE TABLE Requirement (
  reqId VARCHAR, description VARCHAR, importance VARCHAR, validationProcedure VARCHAR);

-- Controls hang off one Requirement; the methodology lives here.
CREATE TABLE Control (
  controlId VARCHAR, reqId VARCHAR, methodology VARCHAR, description VARCHAR);

-- Procedures point at the control they check, not the other way round.
CREATE TABLE StoredProcedures (
  procedureName VARCHAR, controlId VARCHAR);

CREATE TABLE ControlResult (
  timestamp TIMESTAMP, reqId VARCHAR, controlId VARCHAR,
  result BOOLEAN, description VARCHAR);

INSERT INTO Requirement VALUES
  ('REQ-102', 'A transfer is released by an identity different from the one that initiated it.',
   'Must', 'validate_req_102'),
  ('REQ-201', 'An employee in a designated decision-making role takes at least 20 consecutive calendar days of leave each year.',
   'Must', 'validate_req_201');

INSERT INTO Control VALUES
  ('REQ-102-C1', 'REQ-102', 'EARS',    'IF the releasing identity is the same as the initiating identity, THEN the Payment Service SHALL refuse the release and SHALL NOT transmit the payment.'),
  ('REQ-102-C2', 'REQ-102', 'Gherkin', 'Scenario: The initiator cannot release their own transfer
Given a transfer initiated by an employee
When that same employee submits the release
Then the release is refused and the transfer is not transmitted'),
  ('REQ-102-C4', 'REQ-102', 'EARS',    'WHEN a transfer is released, the Payment Service SHALL record both the releasing identity and the release timestamp.'),
  ('REQ-102-C5', 'REQ-102', 'Gherkin', 'Scenario: Every release names who released it and when
Given a transfer that has been released
When its release record is read
Then it carries both a releasing identity and a release timestamp'),
  ('REQ-201-C1', 'REQ-201', 'EARS',    'The Workforce Service SHALL record at least 20 consecutive calendar days of leave per calendar year for every employee in a designated decision-making role.'),
  ('REQ-201-C2', 'REQ-201', 'Gherkin', 'Scenario: Twenty days must be consecutive, not cumulative
Given an employee in a decision-making role whose leave is split into several short periods
When the mandatory leave check runs for the year
Then that employee is reported as non-compliant'),
  ('REQ-201-C4', 'REQ-201', 'EARS',    'The Workforce Service SHALL record leave for every employee in a designated decision-making role.'),
  ('REQ-201-C5', 'REQ-201', 'Gherkin', 'Scenario: Every decision-making role has leave on record
Given an employee in a designated decision-making role
When the mandatory leave check runs for the year
Then at least one leave period is recorded for that employee');

-- One row per control, naming the procedure that checks it.
INSERT INTO StoredProcedures VALUES
  ('check_req_102',                  'REQ-102-C1'),
  ('check_scenario_102',             'REQ-102-C2'),
  ('check_req_102_attribution',      'REQ-102-C4'),
  ('check_scenario_102_attribution', 'REQ-102-C5'),
  ('check_req_201',                  'REQ-201-C1'),
  ('check_scenario_201',             'REQ-201-C2'),
  ('check_req_201_any_leave',        'REQ-201-C4'),
  ('check_scenario_201_any_leave',   'REQ-201-C5');

-- ===== operational data ==============================================
CREATE TABLE Employee (emp_id VARCHAR, name VARCHAR, job_role VARCHAR, decision_maker BOOLEAN);
CREATE TABLE Transfer (transfer_id VARCHAR, amount_eur DECIMAL(12,2), initiated_by VARCHAR, initiated_at DATE);
CREATE TABLE TransferRelease (transfer_id VARCHAR, released_by VARCHAR, released_at DATE);
CREATE TABLE Leaves (employeeId VARCHAR, startDate DATE, endDate DATE);

INSERT INTO Employee VALUES
  ('E-01', 'DANA', 'Treasury Manager', true),
  ('E-02', 'RAVI', 'Payments Officer', false),
  ('E-03', 'MEI',  'Finance Director', true);

INSERT INTO Transfer VALUES
  ('WT-2001', 250000.00, 'E-01', DATE '2026-03-02'),
  ('WT-2002',  88000.00, 'E-03', DATE '2026-03-04');

INSERT INTO TransferRelease VALUES
  ('WT-2001', 'E-02', DATE '2026-03-02'),
  ('WT-2002', 'E-03', DATE '2026-03-04');   -- MEI released her own transfer

-- One row per leave period, not per day.
INSERT INTO Leaves VALUES
  ('E-01', DATE '2026-07-06', DATE '2026-07-27'),
  ('E-03', DATE '2026-02-02', DATE '2026-02-06'),
  ('E-03', DATE '2026-05-04', DATE '2026-05-08'),
  ('E-03', DATE '2026-08-03', DATE '2026-08-07'),
  ('E-03', DATE '2026-11-02', DATE '2026-11-06');

-- ===== use case 1: maker-checker ======================================

-- REQ-102-C1 (EARS). An invariant: any row it returns is a violation.
CREATE MACRO check_req_102() AS TABLE (
  SELECT t.transfer_id, t.amount_eur, e.name AS initiated_and_released_by
    FROM Transfer t
    JOIN TransferRelease r ON r.transfer_id = t.transfer_id
    JOIN Employee e        ON e.emp_id      = t.initiated_by
   WHERE r.released_by = t.initiated_by
);

-- REQ-102-C2 (Gherkin). The scenario text is generic; binding it to rows is
-- this procedure's job. Each case names a transfer and the verdict comes from
-- the rule itself, comparing the releasing identity to the initiating one, so
-- "that same employee" is really tested rather than merely whether a release
-- exists. A transfer released by a second identity reports compliant.
CREATE MACRO check_scenario_102() AS TABLE (
  WITH scenario(name, given_transfer, expected) AS (
    VALUES ('initiator-cannot-release-own-transfer',   'WT-2002', 'compliant'),
           ('a-second-identity-releases-the-transfer', 'WT-2001', 'compliant')
  )
  SELECT s.name AS scenario, s.expected,
         CASE WHEN r.released_by = t.initiated_by
              THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN (CASE WHEN r.released_by = t.initiated_by
                         THEN 'non-compliant' ELSE 'compliant' END)
                   = s.expected THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s
    JOIN Transfer t             ON t.transfer_id = s.given_transfer
    LEFT JOIN TransferRelease r ON r.transfer_id = s.given_transfer
);

-- REQ-102-C4 (EARS, event-driven).
CREATE MACRO check_req_102_attribution() AS TABLE (
  SELECT t.transfer_id, r.released_by, r.released_at
    FROM Transfer t
    JOIN TransferRelease r ON r.transfer_id = t.transfer_id
   WHERE r.released_by IS NULL OR r.released_at IS NULL
);

-- REQ-102-C5 (Gherkin).
CREATE MACRO check_scenario_102_attribution() AS TABLE (
  SELECT t.transfer_id AS scenario, 'compliant' AS expected,
         CASE WHEN r.released_by IS NULL OR r.released_at IS NULL
              THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN r.released_by IS NULL OR r.released_at IS NULL
              THEN 'FAIL' ELSE 'pass' END AS result
    FROM Transfer t LEFT JOIN TransferRelease r ON r.transfer_id = t.transfer_id
);

-- ===== use case 2: mandatory leave ===================================

-- The requirement says "each year", so the year is a parameter and periods
-- are clipped to it before anything is measured: a block running from
-- 20 December to 13 January is 12 days of one year and 13 of the next, and
-- satisfies neither. Adjacent or overlapping periods are one absence, so they
-- are merged into blocks; the length of a block is what the rule asks about.
-- periods clipped to the year, then merged into blocks
CREATE MACRO leave_blocks(yr) AS TABLE (
  WITH clipped AS (
    SELECT employeeId,
           greatest(startDate, make_date(yr,  1,  1)) AS startDate,
           least(   endDate,   make_date(yr, 12, 31)) AS endDate
      FROM Leaves
     WHERE startDate <= make_date(yr, 12, 31)
       AND endDate   >= make_date(yr,  1,  1)),
  ordered AS (
    SELECT employeeId, startDate, endDate,
           max(endDate) OVER (PARTITION BY employeeId ORDER BY startDate
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prevEnd
      FROM clipped),
  blocks AS (
    SELECT employeeId, startDate, endDate,
           sum(CASE WHEN prevEnd IS NULL OR startDate > prevEnd + 1 THEN 1 ELSE 0 END)
             OVER (PARTITION BY employeeId ORDER BY startDate) AS blockId
      FROM ordered)
  SELECT employeeId, datediff('day', min(startDate), max(endDate)) + 1 AS days
    FROM blocks GROUP BY employeeId, blockId
);

-- REQ-201-C1 (EARS).
CREATE MACRO check_req_201(yr) AS TABLE (
  SELECT e.name, e.job_role,
         coalesce(sum(b.days), 0) AS total_leave_days,
         coalesce(max(b.days), 0) AS longest_consecutive_block
    FROM Employee e
    LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker
   GROUP BY e.name, e.job_role
  HAVING coalesce(max(b.days), 0) < 20
);

-- REQ-201-C2 (Gherkin): the same block logic, asserted per named case.
CREATE MACRO check_scenario_201(yr) AS TABLE (
  WITH scenario(name, givenEmp, expected) AS (
    VALUES ('twenty-days-must-be-consecutive',   'E-03', 'non-compliant'),
           ('one-uninterrupted-block-satisfies', 'E-01', 'compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN coalesce(max(b.days), 0) >= 20 THEN 'compliant' ELSE 'non-compliant' END AS actual,
         CASE WHEN (CASE WHEN coalesce(max(b.days), 0) >= 20 THEN 'compliant' ELSE 'non-compliant' END)
                   = s.expected THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s
    LEFT JOIN leave_blocks(yr) b ON b.employeeId = s.givenEmp
   GROUP BY s.name, s.expected
);

-- REQ-201-C4 (EARS, ubiquitous).
CREATE MACRO check_req_201_any_leave(yr) AS TABLE (
  SELECT e.name, e.job_role, count(b.employeeId) AS leave_periods_recorded
    FROM Employee e
    LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker
   GROUP BY e.name, e.job_role
  HAVING count(b.employeeId) = 0
);

-- REQ-201-C5 (Gherkin).
CREATE MACRO check_scenario_201_any_leave(yr) AS TABLE (
  SELECT e.name AS scenario, 'compliant' AS expected,
         CASE WHEN count(b.employeeId) = 0 THEN 'non-compliant'
              ELSE 'compliant' END AS actual,
         CASE WHEN count(b.employeeId) = 0 THEN 'FAIL' ELSE 'pass' END AS result
    FROM Employee e
    LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker
   GROUP BY e.name
);

-- ===== one validation procedure per requirement ======================
-- Runs every control the requirement has and reports a verdict per control.
-- Controls whose procedure is missing or was never written are reported as
-- such rather than silently skipped.
CREATE MACRO validate_req_102() AS TABLE (
              SELECT 'REQ-102-C1' AS controlId, 'EARS' AS methodology,
                     CASE WHEN (SELECT count(*) FROM check_req_102()) = 0
                          THEN 'pass' ELSE 'FAIL' END AS result
    UNION ALL SELECT 'REQ-102-C2', 'Gherkin',
                     CASE WHEN (SELECT count(*) FROM check_scenario_102() WHERE result = 'FAIL') = 0
                          THEN 'pass' ELSE 'FAIL' END
    UNION ALL SELECT 'REQ-102-C4', 'EARS',
                     CASE WHEN (SELECT count(*) FROM check_req_102_attribution()) = 0
                          THEN 'pass' ELSE 'FAIL' END
    UNION ALL SELECT 'REQ-102-C5', 'Gherkin',
                     CASE WHEN (SELECT count(*) FROM check_scenario_102_attribution() WHERE result = 'FAIL') = 0
                          THEN 'pass' ELSE 'FAIL' END
);

CREATE MACRO validate_req_201(yr) AS TABLE (
              SELECT 'REQ-201-C1' AS controlId, 'EARS' AS methodology,
                     CASE WHEN (SELECT count(*) FROM check_req_201(yr)) = 0
                          THEN 'pass' ELSE 'FAIL' END AS result
    UNION ALL SELECT 'REQ-201-C2', 'Gherkin',
                     CASE WHEN (SELECT count(*) FROM check_scenario_201(yr) WHERE result = 'FAIL') = 0
                          THEN 'pass' ELSE 'FAIL' END
    UNION ALL SELECT 'REQ-201-C4', 'EARS',
                     CASE WHEN (SELECT count(*) FROM check_req_201_any_leave(yr)) = 0
                          THEN 'pass' ELSE 'FAIL' END
    UNION ALL SELECT 'REQ-201-C5', 'Gherkin',
                     CASE WHEN (SELECT count(*) FROM check_scenario_201_any_leave(yr) WHERE result = 'FAIL') = 0
                          THEN 'pass' ELSE 'FAIL' END
);

-- ===== evidence: what the scheduled runs recorded =====================
INSERT INTO ControlResult VALUES
  (TIMESTAMP '2026-03-31 02:00:00','REQ-102','REQ-102-C1',false,'WT-2002 (88,000.00 EUR) initiated and released by MEI'),
  (TIMESTAMP '2026-04-30 02:00:00','REQ-102','REQ-102-C1',true, 'No transfer released by its own initiator'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-102','REQ-102-C1',false,'WT-2002 (88,000.00 EUR) initiated and released by MEI'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-102','REQ-102-C2',false,'initiator-cannot-release-own-transfer: expected compliant, got non-compliant'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-201','REQ-201-C1',false,'MEI: 20 leave days in 2026, longest unbroken block 5'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-201','REQ-201-C2',true, 'Both scenarios behaved as specified'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-102','REQ-102-C4',true, 'Every release carries an identity and a timestamp'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-102','REQ-102-C5',true, 'WT-2001 and WT-2002 both attributed'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-201','REQ-201-C4',true, 'DANA and MEI both have leave recorded'),
  (TIMESTAMP '2026-12-31 02:00:00','REQ-201','REQ-201-C5',true, 'Both decision-making roles have leave on record');

-- =====================================================================
-- The eight result tables the post prints, in order.
-- =====================================================================

.print ===POST=== which registered procedures actually exist
SELECT sp.controlId, sp.procedureName,
       CASE WHEN f.function_name IS NULL THEN 'MISSING' ELSE 'ok' END AS in_catalog
  FROM StoredProcedures sp
  LEFT JOIN duckdb_functions() f
         ON f.function_name = sp.procedureName
        AND f.function_type = 'table_macro'
 ORDER BY sp.controlId;

.print ===POST=== REQ-102-C1 (EARS)
SELECT * FROM check_req_102();

.print ===POST=== REQ-102-C2 (Gherkin)
SELECT * FROM check_scenario_102() ORDER BY scenario;

.print ===POST=== REQ-201-C1 (EARS)
SELECT * FROM check_req_201(2026);

.print ===POST=== REQ-201-C2 (Gherkin)
SELECT * FROM check_scenario_201(2026) ORDER BY scenario;

.print ===POST=== validate_req_102()
SELECT * FROM validate_req_102() ORDER BY controlId;

.print ===POST=== validate_req_201(2026)
SELECT * FROM validate_req_201(2026) ORDER BY controlId;

.print ===POST=== the register, answered
WITH latest AS (
  SELECT controlId, arg_max(result, timestamp) AS result, max(timestamp) AS ts
    FROM ControlResult GROUP BY controlId
)
SELECT r.reqId, r.importance,
       count(DISTINCT c.controlId)  AS controls,
       count(DISTINCT sp.controlId) AS with_procedure,
       coalesce(CAST(max(l.ts) AS VARCHAR), '(never run)') AS last_run,
       CASE WHEN count(DISTINCT l.controlId) = 0 THEN '(no evidence)'
            WHEN NOT bool_and(l.result)            THEN 'FAIL'
            WHEN count(DISTINCT l.controlId)
                 < count(DISTINCT c.controlId)     THEN 'incomplete'
            ELSE 'pass' END AS verdict
  FROM Requirement r
  LEFT JOIN Control c            ON c.reqId      = r.reqId
  LEFT JOIN StoredProcedures sp  ON sp.controlId = c.controlId
  LEFT JOIN latest l             ON l.controlId  = c.controlId
 GROUP BY r.reqId, r.importance
 ORDER BY r.reqId;
