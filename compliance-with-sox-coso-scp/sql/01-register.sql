-- Layers 1-4 of the register: the statute, the COSO governance, the SCF
-- catalog and the OSCAL evidence tables. No operational data here.

-- Wall-clock marks, so the run reports how long each phase took rather
-- than leaving it to a stopwatch. Building the population and checking it
-- are very different costs, and only the second one recurs at period end.
CREATE TABLE RunPhase (phase VARCHAR, markedAt TIMESTAMP);
INSERT INTO RunPhase VALUES ('start', get_current_timestamp());

-- ===== layer 1 . regulation: the statutory obligation ================
-- Section and subsection are separate columns rather than one '404(a)'
-- string, so a control traces to the subsection it discharges and a roll-up
-- can group by section without parsing text.
CREATE TABLE Mandate (
  mandateId VARCHAR, authority VARCHAR, section VARCHAR, subsection VARCHAR,
  obligation VARCHAR);

INSERT INTO Mandate VALUES
  ('SOX-404a', 'SOX', '404', 'a',
   'Management assesses the effectiveness of internal control over financial reporting against a suitable, recognized framework.'),
  ('SOX-404b', 'SOX', '404', 'b',
   'The registered public accounting firm attests to that assessment.');

-- ===== layer 2 . governance: the register, expressed in COSO =========
CREATE TABLE Requirement (
  reqId VARCHAR, description VARCHAR, importance VARCHAR, validationProcedure VARCHAR);

-- Each requirement answers to one subsection of the statute through one COSO
-- principle: mandateId up to layer 1, cosoPrinciple across layer 2. SOX-404b
-- has no rows here on purpose - it is the auditor's obligation, not one our
-- controls discharge.
CREATE TABLE RequirementGovernance (
  reqId VARCHAR, mandateId VARCHAR, cosoComponent VARCHAR,
  cosoPrinciple INTEGER, principleText VARCHAR);

INSERT INTO Requirement VALUES
  ('REQ-301', 'Every intercompany transaction is recorded by both entities and the two legs reconcile in the reporting currency before consolidation.',
   'Must', 'validate_req_301'),
  ('REQ-302', 'The identity that posts one leg of an intercompany transaction does not post the opposing leg.',
   'Must', 'validate_req_302'),
  ('REQ-303', 'Every translated intercompany amount carries the rate, the rate source and the timestamp it was taken at.',
   'Must', 'validate_req_303');

INSERT INTO RequirementGovernance VALUES
  ('REQ-301', 'SOX-404a', 'Information & Communication', 13,
   'The organization obtains or generates and uses relevant, quality information to support the functioning of internal control.'),
  ('REQ-302', 'SOX-404a', 'Control Activities', 10,
   'The organization selects and develops control activities that contribute to the mitigation of risks to the achievement of objectives to acceptable levels.'),
  ('REQ-303', 'SOX-404a', 'Control Activities', 11,
   'The organization selects and develops general control activities over technology to support the achievement of objectives.');

-- ===== layer 3 . controls: the SCF catalog ===========================
-- In practice this table is loaded from the SCF catalog. ORG- marks an
-- organization-defined control: intercompany matching is a financial
-- reporting control, so the SCF catalog does not carry it.
CREATE TABLE ControlCatalog (
  scfId VARCHAR, domain VARCHAR, name VARCHAR, source VARCHAR);

INSERT INTO ControlCatalog VALUES
  ('ORG-DCH-01', 'Data Classification & Handling', 'Intercompany Matching & Validation', 'organization-defined'),
  ('HRS-11',     'Human Resources Security',       'Separation of Duties (SoD)',         'SCF'),
  ('MON-03.2',   'Continuous Monitoring',          'Audit Trails',                       'SCF');

-- The SOX 404 ICFR baseline: which catalog controls are in scope at all.
CREATE TABLE Profile (profileId VARCHAR, scfId VARCHAR);
INSERT INTO Profile VALUES
  ('sox-404-icfr', 'ORG-DCH-01'),
  ('sox-404-icfr', 'HRS-11'),
  ('sox-404-icfr', 'MON-03.2');

-- One control per EARS sentence or Gherkin scenario, bound to a catalog entry.
CREATE TABLE Control (
  controlId VARCHAR, reqId VARCHAR, scfId VARCHAR,
  methodology VARCHAR, description VARCHAR);

INSERT INTO Control VALUES
  ('REQ-301-C1', 'REQ-301', 'ORG-DCH-01', 'EARS',
   'IF the selling entity has not recorded a leg, OR the buying entity has not recorded a leg, OR either amount is absent in the reporting currency, OR the two amounts differ by more than 1 USD, THEN the Consolidation Service SHALL reject the intercompany transaction.'),
  ('REQ-301-C2', 'REQ-301', 'ORG-DCH-01', 'Gherkin',
   'Scenario: An unmatched intercompany leg blocks consolidation
Given an intercompany reference recorded by the selling entity
When the buying entity has not recorded the opposing leg
Then the reference is reported as unmatched and consolidation is halted'),
  ('REQ-302-C1', 'REQ-302', 'HRS-11', 'EARS',
   'IF the identity that posted an opposing leg is not recorded, OR it is the same identity that posted the first leg, THEN the Consolidation Service SHALL refuse the posting.'),
  ('REQ-302-C2', 'REQ-302', 'HRS-11', 'Gherkin',
   'Scenario: One identity cannot post both sides
Given an intercompany reference with a leg in each entity
When the two legs name the same posting identity
Then the reference is reported as a segregation-of-duties breach'),
  ('REQ-303-C1', 'REQ-303', 'MON-03.2', 'EARS',
   'IF a posted leg does not record the rate, OR does not record the rate source, OR does not record the timestamp the rate was taken at, THEN the Consolidation Service SHALL reject the leg.'),
  ('REQ-303-C2', 'REQ-303', 'MON-03.2', 'Gherkin',
   'Scenario: Every translated amount can be recomputed
Given a posted intercompany leg
When its translation record is read
Then it carries a rate, a source and the timestamp the rate was taken at');

CREATE TABLE StoredProcedures (procedureName VARCHAR, controlId VARCHAR);
INSERT INTO StoredProcedures VALUES
  ('check_req_301',      'REQ-301-C1'),
  ('check_scenario_301', 'REQ-301-C2'),
  ('check_req_302',      'REQ-302-C1'),
  ('check_scenario_302', 'REQ-302-C2'),
  ('check_req_303',      'REQ-303-C1'),
  ('check_scenario_303', 'REQ-303-C2');

-- ===== layer 4 . evidence: OSCAL assessment-results ==================
CREATE TABLE Observation (
  uuid UUID, collected TIMESTAMP, method VARCHAR, type VARCHAR,
  controlId VARCHAR, description VARCHAR, evidenceHref VARCHAR);

-- A finding is the judgement against one control objective. It relates to
-- however many observations the run produced for that control, so the link
-- is controlId rather than a single observation uuid.
CREATE TABLE Finding (
  uuid UUID, controlId VARCHAR, targetType VARCHAR, targetId VARCHAR,
  state VARCHAR, reason VARCHAR, title VARCHAR);
