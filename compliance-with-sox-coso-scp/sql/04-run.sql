-- =====================================================================
-- The assessment run.
--
-- Each procedure is executed exactly once and its output is materialised,
-- because at group volume the EARS invariants aggregate ten million legs
-- and calling them once per column of a report is the difference between
-- seconds and minutes. The materialised exception tables are also what an
-- auditor actually wants: the exception report, kept, not recomputed.
-- =====================================================================

CREATE TABLE Ex301 AS SELECT * FROM check_req_301();
CREATE TABLE Ex302 AS SELECT * FROM check_req_302();
CREATE TABLE Ex303 AS SELECT * FROM check_req_303();

CREATE TABLE Sc301 AS SELECT * FROM check_scenario_301();
CREATE TABLE Sc302 AS SELECT * FROM check_scenario_302();
CREATE TABLE Sc303 AS SELECT * FROM check_scenario_303();

-- A finding names the exceptions it is about, but an OSCAL description is
-- read by a person: three references and a count, not a hundred thousand
-- identifiers. Under the cap the text is the full list, so the five-row
-- example reads exactly as it always did.
CREATE MACRO detail_head(n) AS (
  CASE WHEN n > 3 THEN '; and ' || (n - 3)::VARCHAR || ' more' ELSE '' END);

-- One row per control: what the procedure saw, and the OSCAL verdict.
CREATE MACRO assessment() AS TABLE (
              SELECT 'REQ-301-C1' AS controlId, 'check_req_301' AS procedureName,
                     CASE WHEN (SELECT count(*) FROM Ex301) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END AS state,
                     coalesce((SELECT string_agg(icRefId || ': ' || reason || ' (variance '
                                                 || money(variance_usd) || ' USD)', '; ' ORDER BY icRefId)
                                 FROM (SELECT * FROM Ex301 ORDER BY icRefId LIMIT 3))
                              || detail_head((SELECT count(*) FROM Ex301)),
                              'Every intercompany reference has two legs agreeing within 1 USD') AS detail
    UNION ALL SELECT 'REQ-301-C2', 'check_scenario_301',
                     CASE WHEN (SELECT count(*) FROM Sc301 WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(scenario || ': got ' || actual, '; ')
                                 FROM Sc301 WHERE result = 'FAIL'),
                              'All ' || (SELECT count(*) FROM Sc301)::VARCHAR
                                     || ' scenarios behaved as specified')
    UNION ALL SELECT 'REQ-302-C1', 'check_req_302',
                     CASE WHEN (SELECT count(*) FROM Ex302) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(icRefId || ': ' || reason
                                                 || coalesce(' (' || ar_posted_by || ')', ''), '; ' ORDER BY icRefId)
                                 FROM (SELECT * FROM Ex302 ORDER BY icRefId LIMIT 3))
                              || detail_head((SELECT count(*) FROM Ex302)),
                              'No intercompany reference has both legs posted by one identity')
    UNION ALL SELECT 'REQ-302-C2', 'check_scenario_302',
                     CASE WHEN (SELECT count(*) FROM Sc302 WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(scenario || ': got ' || actual, '; ')
                                 FROM Sc302 WHERE result = 'FAIL'),
                              'All ' || (SELECT count(*) FROM Sc302)::VARCHAR
                                     || ' scenarios behaved as specified')
    UNION ALL SELECT 'REQ-303-C1', 'check_req_303',
                     CASE WHEN (SELECT count(*) FROM Ex303) = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(entryId || ': ' || reason, '; ' ORDER BY entryId)
                                 FROM (SELECT * FROM Ex303 ORDER BY entryId LIMIT 3))
                              || detail_head((SELECT count(*) FROM Ex303)),
                              'Every posted leg carries a rate, a source and a timestamp')
    UNION ALL SELECT 'REQ-303-C2', 'check_scenario_303',
                     CASE WHEN (SELECT count(*) FROM Sc303 WHERE result = 'FAIL') = 0
                          THEN 'satisfied' ELSE 'not-satisfied' END,
                     coalesce((SELECT string_agg(scenario || ': got ' || actual, '; ')
                                 FROM (SELECT * FROM Sc303 WHERE result = 'FAIL' ORDER BY scenario LIMIT 3))
                              || detail_head((SELECT count(*) FROM Sc303 WHERE result = 'FAIL')),
                              'All ' || (SELECT count(*) FROM Sc303)::VARCHAR
                                     || ' scenarios behaved as specified'));

-- Each requirement names one procedure that runs all of its controls.
CREATE MACRO validate_req_301() AS TABLE (SELECT * FROM assessment() WHERE controlId LIKE 'REQ-301-%');
CREATE MACRO validate_req_302() AS TABLE (SELECT * FROM assessment() WHERE controlId LIKE 'REQ-302-%');
CREATE MACRO validate_req_303() AS TABLE (SELECT * FROM assessment() WHERE controlId LIKE 'REQ-303-%');

-- The assessment is itself materialised: six rows, read by the report, the
-- observations, the findings and the OSCAL export.
CREATE TABLE AssessmentRun AS SELECT * FROM assessment();

-- Every exception, in one shape, so an observation can be written per issue
-- rather than one per control with the issues concatenated into its text.
-- `magnitude` orders them: the largest break is the one an auditor opens.
CREATE TABLE ExceptionRow AS
            SELECT 'REQ-301-C1' AS controlId, 'check_req_301' AS procedureName,
                   icRefId AS ref,
                   icRefId || ': ' || reason || ' (variance ' || money(variance_usd) || ' USD)' AS description,
                   abs(variance_usd) AS magnitude
              FROM Ex301
  UNION ALL SELECT 'REQ-302-C1', 'check_req_302', icRefId,
                   icRefId || ': ' || reason || coalesce(' (' || ar_posted_by || ')', ''), 0 FROM Ex302
  UNION ALL SELECT 'REQ-303-C1', 'check_req_303', entryId,
                   entryId || ': ' || reason, 0 FROM Ex303
  UNION ALL SELECT 'REQ-301-C2', 'check_scenario_301', scenario,
                   scenario || ': expected ' || expected || ', got ' || actual, 0
              FROM Sc301 WHERE result = 'FAIL'
  UNION ALL SELECT 'REQ-302-C2', 'check_scenario_302', scenario,
                   scenario || ': expected ' || expected || ', got ' || actual, 0
              FROM Sc302 WHERE result = 'FAIL'
  UNION ALL SELECT 'REQ-303-C2', 'check_scenario_303', scenario,
                   scenario || ': expected ' || expected || ', got ' || actual, 0
              FROM Sc303 WHERE result = 'FAIL';

-- An OSCAL document is read by a person. At group volume the exception
-- population runs to six figures, so the document carries the largest
-- `observation_cap` per control and the CSV carries the rest.
SET VARIABLE observation_cap = coalesce(getvariable('observation_cap'), 10);

-- Observations: what was seen. A failing control contributes one per
-- exception; a satisfied control contributes one saying what held.
INSERT INTO Observation
            SELECT uuid(), TIMESTAMP '2026-12-31 02:00:00', 'TEST', 'control-objective',
                   controlId, description,
                   'sql://procedure/' || procedureName || '#' || ref
              FROM (SELECT *, row_number() OVER (PARTITION BY controlId
                                                 ORDER BY magnitude DESC, ref) AS rn
                      FROM ExceptionRow)
             WHERE rn <= getvariable('observation_cap')
  UNION ALL SELECT uuid(), TIMESTAMP '2026-12-31 02:00:00', 'TEST', 'control-objective',
                   a.controlId, a.detail, 'sql://procedure/' || a.procedureName
              FROM AssessmentRun a
             WHERE a.state = 'satisfied';

-- Findings: what it means. One per control, whatever the exception count -
-- the finding is the judgement against the control objective, and the
-- observations above are the evidence it relates to.
INSERT INTO Finding
SELECT uuid(), a.controlId, 'objective-id',
       lower(c.scfId) || '_obj', a.state,
       CASE WHEN a.state = 'satisfied' THEN 'pass' ELSE 'fail' END,
       c.scfId || ' - ' || cc.name || ' (' || a.controlId || ')'
  FROM AssessmentRun a
  JOIN Control c         ON c.controlId = a.controlId
  JOIN ControlCatalog cc ON cc.scfId    = c.scfId;

INSERT INTO RunPhase VALUES ('checked', get_current_timestamp());
