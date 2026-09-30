-- =====================================================================
-- Compliance With Standards
-- Companion script: the register from "Towards Repeatable Compliance",
-- rebound to SOX/COSO (layer 1), the Secure Controls Framework (layer 2)
-- and NIST OSCAL assessment-results (layer 3).
--
--   duckdb < standards-validation.sql
--
-- The operational tables and every check procedure are unchanged from the
-- first post. Only the register around them moves.
-- =====================================================================

-- ===== layer 1 . governance: SOX, expressed in COSO ==================
CREATE TABLE Requirement (
  reqId VARCHAR, description VARCHAR, importance VARCHAR, validationProcedure VARCHAR);

CREATE TABLE RequirementGovernance (
  reqId VARCHAR, authority VARCHAR, cosoComponent VARCHAR,
  cosoPrinciple INTEGER, principleText VARCHAR);

INSERT INTO Requirement VALUES
  ('REQ-102', 'A transfer is released by an identity different from the one that initiated it.',
   'Must', 'validate_req_102'),
  ('REQ-201', 'An employee in a designated decision-making role takes at least 20 consecutive calendar days of leave each year.',
   'Must', 'validate_req_201');

INSERT INTO RequirementGovernance VALUES
  ('REQ-102', 'SOX-404', 'Control Activities', 10,
   'The organization selects and develops control activities that contribute to the mitigation of risks to the achievement of objectives to acceptable levels.'),
  ('REQ-102', 'SOX-404', 'Control Activities', 12,
   'The organization deploys control activities through policies that establish what is expected and procedures that put policies into action.'),
  ('REQ-201', 'SOX-404', 'Control Activities', 10,
   'The organization selects and develops control activities that contribute to the mitigation of risks to the achievement of objectives to acceptable levels.'),
  ('REQ-201', 'SOX-404', 'Monitoring Activities', 16,
   'The organization selects, develops and performs ongoing and/or separate evaluations to ascertain whether the components of internal control are present and functioning.');

-- ===== layer 2 . controls: the SCF catalog ===========================
-- In practice this table is loaded from the SCF OSCAL catalog JSON.
CREATE TABLE ControlCatalog (
  scfId VARCHAR, domain VARCHAR, name VARCHAR, source VARCHAR);

INSERT INTO ControlCatalog VALUES
  ('HRS-11',    'Human Resources Security', 'Separation of Duties (SoD)', 'SCF'),
  ('HRS-12',    'Human Resources Security', 'Incompatible Roles',         'SCF'),
  ('HRS-12.1',  'Human Resources Security', 'Two-Person Rule',            'SCF'),
  ('HRS-02',    'Human Resources Security', 'Position Categorization',    'SCF'),
  ('IAC-01',    'Identification & Authentication', 'Identity & Access Management', 'SCF'),
  ('MON-03',    'Continuous Monitoring',    'Content of Event Logs',      'SCF'),
  ('MON-03.2',  'Continuous Monitoring',    'Audit Trails',               'SCF'),
  ('ORG-HRS-01','Human Resources Security', 'Mandatory Consecutive Leave','organization-defined');

-- The SOX ITGC baseline: which catalog controls are in scope at all.
CREATE TABLE Profile (profileId VARCHAR, scfId VARCHAR);
INSERT INTO Profile VALUES
  ('sox-404-itgc', 'HRS-11'),
  ('sox-404-itgc', 'HRS-12.1'),
  ('sox-404-itgc', 'IAC-01'),
  ('sox-404-itgc', 'MON-03'),
  ('sox-404-itgc', 'MON-03.2'),
  ('sox-404-itgc', 'ORG-HRS-01');

-- Control gains one column: the catalog entry it implements.
CREATE TABLE Control (
  controlId VARCHAR, reqId VARCHAR, scfId VARCHAR,
  methodology VARCHAR, description VARCHAR);

INSERT INTO Control VALUES
  ('REQ-102-C1', 'REQ-102', 'HRS-11',    'EARS',    'IF the releasing identity is the same as the initiating identity, THEN the Payment Service SHALL refuse the release and SHALL NOT transmit the payment.'),
  ('REQ-102-C2', 'REQ-102', 'HRS-11',    'Gherkin', 'Scenario: The initiator cannot release their own transfer'),
  ('REQ-102-C4', 'REQ-102', 'MON-03.2',  'EARS',    'WHEN a transfer is released, the Payment Service SHALL record both the releasing identity and the release timestamp.'),
  ('REQ-102-C5', 'REQ-102', 'MON-03.2',  'Gherkin', 'Scenario: Every release names who released it and when'),
  ('REQ-201-C1', 'REQ-201', 'ORG-HRS-01','EARS',    'The Workforce Service SHALL record at least 20 consecutive calendar days of leave per calendar year for every employee in a designated decision-making role.'),
  ('REQ-201-C2', 'REQ-201', 'ORG-HRS-01','Gherkin', 'Scenario: Twenty days must be consecutive, not cumulative'),
  ('REQ-201-C4', 'REQ-201', 'ORG-HRS-01','EARS',    'The Workforce Service SHALL record leave for every employee in a designated decision-making role.'),
  ('REQ-201-C5', 'REQ-201', 'ORG-HRS-01','Gherkin', 'Scenario: Every decision-making role has leave on record');

CREATE TABLE StoredProcedures (procedureName VARCHAR, controlId VARCHAR);
INSERT INTO StoredProcedures VALUES
  ('check_req_102',                  'REQ-102-C1'),
  ('check_scenario_102',             'REQ-102-C2'),
  ('check_req_102_attribution',      'REQ-102-C4'),
  ('check_scenario_102_attribution', 'REQ-102-C5'),
  ('check_req_201',                  'REQ-201-C1'),
  ('check_scenario_201',             'REQ-201-C2'),
  ('check_req_201_any_leave',        'REQ-201-C4'),
  ('check_scenario_201_any_leave',   'REQ-201-C5');

-- ===== layer 3 . evidence: OSCAL assessment-results ==================
-- ControlResult splits in two, because OSCAL splits it in two.
CREATE TABLE Observation (
  uuid UUID, collected TIMESTAMP, method VARCHAR, type VARCHAR,
  controlId VARCHAR, description VARCHAR, evidenceHref VARCHAR);

CREATE TABLE Finding (
  uuid UUID, observationUuid UUID, targetType VARCHAR, targetId VARCHAR,
  state VARCHAR, reason VARCHAR, title VARCHAR);

-- ===== operational data (unchanged) ==================================
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
  ('WT-2002', 'E-03', DATE '2026-03-04');
INSERT INTO Leaves VALUES
  ('E-01', DATE '2026-07-06', DATE '2026-07-27'),
  ('E-03', DATE '2026-02-02', DATE '2026-02-06'),
  ('E-03', DATE '2026-05-04', DATE '2026-05-08'),
  ('E-03', DATE '2026-08-03', DATE '2026-08-07'),
  ('E-03', DATE '2026-11-02', DATE '2026-11-06');

-- ===== the check procedures (unchanged) ==============================
CREATE MACRO check_req_102() AS TABLE (
  SELECT t.transfer_id, t.amount_eur, e.name AS initiated_and_released_by
    FROM Transfer t
    JOIN TransferRelease r ON r.transfer_id = t.transfer_id
    JOIN Employee e        ON e.emp_id      = t.initiated_by
   WHERE r.released_by = t.initiated_by);

CREATE MACRO check_scenario_102() AS TABLE (
  WITH scenario(name, given_transfer, expected) AS (
    VALUES ('initiator-cannot-release-own-transfer',   'WT-2002', 'compliant'),
           ('a-second-identity-releases-the-transfer', 'WT-2001', 'compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN r.released_by = t.initiated_by THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN (CASE WHEN r.released_by = t.initiated_by THEN 'non-compliant' ELSE 'compliant' END)
                   = s.expected THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s
    JOIN Transfer t             ON t.transfer_id = s.given_transfer
    LEFT JOIN TransferRelease r ON r.transfer_id = s.given_transfer);

CREATE MACRO check_req_102_attribution() AS TABLE (
  SELECT t.transfer_id, r.released_by, r.released_at
    FROM Transfer t JOIN TransferRelease r ON r.transfer_id = t.transfer_id
   WHERE r.released_by IS NULL OR r.released_at IS NULL);

CREATE MACRO check_scenario_102_attribution() AS TABLE (
  SELECT t.transfer_id AS scenario, 'compliant' AS expected,
         CASE WHEN r.released_by IS NULL OR r.released_at IS NULL THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN r.released_by IS NULL OR r.released_at IS NULL THEN 'FAIL' ELSE 'pass' END AS result
    FROM Transfer t LEFT JOIN TransferRelease r ON r.transfer_id = t.transfer_id);

CREATE MACRO leave_blocks(yr) AS TABLE (
  WITH clipped AS (
    SELECT employeeId,
           greatest(startDate, make_date(yr,  1,  1)) AS startDate,
           least(   endDate,   make_date(yr, 12, 31)) AS endDate
      FROM Leaves
     WHERE startDate <= make_date(yr, 12, 31) AND endDate >= make_date(yr, 1, 1)),
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
    FROM blocks GROUP BY employeeId, blockId);

CREATE MACRO check_req_201(yr) AS TABLE (
  SELECT e.name, e.job_role,
         coalesce(sum(b.days), 0) AS total_leave_days,
         coalesce(max(b.days), 0) AS longest_consecutive_block
    FROM Employee e LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker GROUP BY e.name, e.job_role
  HAVING coalesce(max(b.days), 0) < 20);

CREATE MACRO check_scenario_201(yr) AS TABLE (
  WITH scenario(name, givenEmp, expected) AS (
    VALUES ('twenty-days-must-be-consecutive',   'E-03', 'non-compliant'),
           ('one-uninterrupted-block-satisfies', 'E-01', 'compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN coalesce(max(b.days), 0) >= 20 THEN 'compliant' ELSE 'non-compliant' END AS actual,
         CASE WHEN (CASE WHEN coalesce(max(b.days), 0) >= 20 THEN 'compliant' ELSE 'non-compliant' END)
                   = s.expected THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s LEFT JOIN leave_blocks(yr) b ON b.employeeId = s.givenEmp
   GROUP BY s.name, s.expected);

CREATE MACRO check_req_201_any_leave(yr) AS TABLE (
  SELECT e.name, e.job_role, count(b.employeeId) AS leave_periods_recorded
    FROM Employee e LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker GROUP BY e.name, e.job_role
  HAVING count(b.employeeId) = 0);

CREATE MACRO check_scenario_201_any_leave(yr) AS TABLE (
  SELECT e.name AS scenario, 'compliant' AS expected,
         CASE WHEN count(b.employeeId) = 0 THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN count(b.employeeId) = 0 THEN 'FAIL' ELSE 'pass' END AS result
    FROM Employee e LEFT JOIN leave_blocks(yr) b ON b.employeeId = e.emp_id
   WHERE e.decision_maker GROUP BY e.name);

-- ===== the assessment run ============================================
-- One row per control: what the procedure saw, and the OSCAL verdict.
CREATE MACRO assessment(yr) AS TABLE (
              SELECT 'REQ-102-C1' AS controlId, 'check_req_102' AS procedureName,
                     CASE WHEN (SELECT count(*) FROM check_req_102()) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END AS state,
                     coalesce((SELECT string_agg(transfer_id || ' (' || amount_eur || ' EUR) initiated and released by ' || initiated_and_released_by, '; ')
                                 FROM check_req_102()),
                              'No transfer released by its own initiator') AS detail
    UNION ALL SELECT 'REQ-102-C2', 'check_scenario_102',
                     CASE WHEN (SELECT count(*) FROM check_scenario_102() WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(scenario || ': got ' || actual, '; ')
                                 FROM check_scenario_102() WHERE result = 'FAIL'),
                              'Both scenarios behaved as specified')
    UNION ALL SELECT 'REQ-102-C4', 'check_req_102_attribution',
                     CASE WHEN (SELECT count(*) FROM check_req_102_attribution()) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     'Every release carries an identity and a timestamp'
    UNION ALL SELECT 'REQ-102-C5', 'check_scenario_102_attribution',
                     CASE WHEN (SELECT count(*) FROM check_scenario_102_attribution() WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     'WT-2001 and WT-2002 both attributed'
    UNION ALL SELECT 'REQ-201-C1', 'check_req_201',
                     CASE WHEN (SELECT count(*) FROM check_req_201(yr)) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(name || ': ' || total_leave_days || ' leave days, longest unbroken block '
                                                 || longest_consecutive_block, '; ')
                                 FROM check_req_201(yr)),
                              'Every decision-making role took 20 consecutive days')
    UNION ALL SELECT 'REQ-201-C2', 'check_scenario_201',
                     CASE WHEN (SELECT count(*) FROM check_scenario_201(yr) WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     'Both scenarios behaved as specified'
    UNION ALL SELECT 'REQ-201-C4', 'check_req_201_any_leave',
                     CASE WHEN (SELECT count(*) FROM check_req_201_any_leave(yr)) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     'DANA and MEI both have leave recorded'
    UNION ALL SELECT 'REQ-201-C5', 'check_scenario_201_any_leave',
                     CASE WHEN (SELECT count(*) FROM check_scenario_201_any_leave(yr) WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     'Both decision-making roles have leave on record');

-- The run writes an Observation (what was seen) and a Finding (what it means).
INSERT INTO Observation
SELECT uuid(), TIMESTAMP '2026-12-31 02:00:00', 'TEST', 'control-objective',
       a.controlId, a.detail, 'sql://procedure/' || a.procedureName
  FROM assessment(2026) a;

INSERT INTO Finding
SELECT uuid(), o.uuid, 'objective-id',
       lower(c.scfId) || '_obj', a.state,
       CASE WHEN a.state = 'satisfied' THEN 'pass' ELSE 'fail' END,
       c.scfId || ' - ' || cc.name || ' (' || a.controlId || ')'
  FROM assessment(2026) a
  JOIN Control c         ON c.controlId = a.controlId
  JOIN ControlCatalog cc ON cc.scfId    = c.scfId
  JOIN Observation o     ON o.controlId = a.controlId;

-- =====================================================================
-- The result tables the post prints.
-- =====================================================================

.print ===POST=== 1. the register read top down: SOX to COSO to SCF
SELECT g.authority, g.cosoComponent, g.cosoPrinciple AS principle,
       r.reqId, c.scfId, cc.name AS scf_control, count(*) AS controls
  FROM Requirement r
  JOIN RequirementGovernance g ON g.reqId = r.reqId
  JOIN Control c               ON c.reqId = r.reqId
  JOIN ControlCatalog cc       ON cc.scfId = c.scfId
 GROUP BY ALL ORDER BY r.reqId, g.cosoPrinciple, c.scfId;

.print ===POST=== 2. coverage of the SOX ITGC baseline
SELECT p.scfId, cc.name,               -- the ORG- prefix marks what is not SCF
       count(c.controlId) AS controls,
       CASE WHEN count(c.controlId) = 0 THEN 'NOT IMPLEMENTED' ELSE 'implemented' END AS status
  FROM Profile p
  JOIN ControlCatalog cc ON cc.scfId = p.scfId
  LEFT JOIN Control c    ON c.scfId  = p.scfId
 WHERE p.profileId = 'sox-404-itgc'
 GROUP BY ALL ORDER BY p.scfId;

.print ===POST=== 3. OSCAL findings, most recent run
SELECT f.targetId, f.state, o.description
  FROM Finding f JOIN Observation o ON o.uuid = f.observationUuid
 ORDER BY f.targetId, f.state, o.controlId;

.print ===POST=== 4. SOX 404 roll-up by COSO principle
SELECT g.cosoComponent, g.cosoPrinciple AS principle,
       count(DISTINCT c.controlId) AS controls,
       count(DISTINCT CASE WHEN f.state = 'not-satisfied' THEN c.controlId END) AS not_satisfied,
       CASE WHEN count(DISTINCT CASE WHEN f.state = 'not-satisfied' THEN c.controlId END) > 0
            THEN 'DEFICIENCY' ELSE 'effective' END AS conclusion
  FROM RequirementGovernance g
  JOIN Control c     ON c.reqId = g.reqId
  JOIN Observation o ON o.controlId = c.controlId
  JOIN Finding f     ON f.observationUuid = o.uuid
 WHERE g.authority = 'SOX-404'
 GROUP BY ALL ORDER BY g.cosoPrinciple;

.print ===POST=== 5. the OSCAL assessment-results export
.mode line
SELECT to_json({
  'uuid': '11111111-1111-4111-8111-111111111111',
  'metadata': {
     'title': 'SOX 404 ITGC assessment - FY2026',
     'last-modified': strftime(max(o.collected), '%Y-%m-%dT%H:%M:%SZ'),
     'version': '1.0', 'oscal-version': '1.1.2'},
  'import-ap': {'href': '#sox-404-itgc-assessment-plan'},
  'results': [{
     'uuid': '22222222-2222-4222-8222-222222222222',
     'title': 'Scheduled control run',
     'description': 'Automated execution of the registered SQL procedures.',
     'start': strftime(max(o.collected), '%Y-%m-%dT%H:%M:%SZ'),
     'reviewed-controls': {'control-selections': [
        {'include-controls': list(DISTINCT {'control-id': lower(c.scfId)})}]},
     'observations': list({'uuid': o.uuid, 'methods': ['TEST'],
        'types': ['control-objective'], 'description': o.description,
        'collected': strftime(o.collected, '%Y-%m-%dT%H:%M:%SZ'),
        'relevant-evidence': [{'href': o.evidenceHref,
                               'description': 'Output of ' || o.evidenceHref}]}),
     'findings': list({'uuid': f.uuid, 'title': f.title,
        'description': o.description,
        'target': {'type': 'objective-id', 'target-id': f.targetId,
                   'status': {'state': f.state, 'reason': f.reason}},
        'related-observations': [{'observation-uuid': o.uuid}]})}]
  }) AS assessment_results
  FROM Observation o
  JOIN Finding f ON f.observationUuid = o.uuid
  JOIN Control c ON c.controlId = o.controlId;
