-- The OSCAL assessment-results document. Shared by both reports.
--
-- A failing control produces one observation per exception, so REQ-301-C1
-- carries IC-1002 and IC-1003 as two separate entries rather than one entry
-- with both concatenated into its text. The finding stays single - it is the
-- judgement against the control objective - and lists every observation it
-- rests on in related-observations.
--
-- Both carry the register above them. An observation or a finding names the
-- requirement it came from and the statute subsection that requirement
-- discharges, as props for a reader and as links into back-matter for a
-- tool. That is the chain the post walks - SOX 404(a) to a COSO principle to
-- an SCF control to a transaction - travelling with the evidence instead of
-- staying behind in our database.

-- Each finding's evidence, gathered before the document is assembled.
CREATE TABLE FindingObservation AS
SELECT f.uuid AS findingUuid, o.uuid AS observationUuid
  FROM Finding f JOIN Observation o ON o.controlId = f.controlId;

-- ===== the OSCAL assessment-results export ===========================
COPY (
WITH trace AS (
  -- one row per control, carrying everything above it in the register
  SELECT c.controlId, c.scfId, c.methodology,
         r.reqId, r.description AS reqText,
         g.cosoComponent, g.cosoPrinciple,
         m.mandateId, m.authority, m.section, m.subsection, m.obligation
    FROM Control c
    JOIN Requirement r           ON r.reqId     = c.reqId
    JOIN RequirementGovernance g ON g.reqId     = c.reqId
    JOIN Mandate m               ON m.mandateId = g.mandateId),
obs AS (
  SELECT t.scfId,
         {'uuid': o.uuid, 'methods': ['TEST'], 'types': ['control-objective'],
          'description': o.description,
          'props': [
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'control-id',     'value': o.controlId},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'requirement-id', 'value': t.reqId},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'mandate-id',     'value': t.mandateId}],
          'links': [
             {'rel': 'requirement', 'href': '#' || uuid_of(t.reqId),     'text': t.reqId},
             {'rel': 'mandate',     'href': '#' || uuid_of(t.mandateId),
              'text': t.authority || ' ' || t.section || '(' || t.subsection || ')'}],
          'collected': strftime(o.collected, '%Y-%m-%dT%H:%M:%SZ'),
          'relevant-evidence': [{'href': o.evidenceHref,
                                 'description': 'Output of ' || o.evidenceHref}]} AS entry
    FROM Observation o JOIN trace t ON t.controlId = o.controlId),
fin AS (
  SELECT {'uuid': f.uuid, 'title': f.title,
          'description': a.detail,
          'props': [
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'control-id',     'value': f.controlId},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'requirement-id', 'value': t.reqId},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'methodology',    'value': t.methodology},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'coso-component', 'value': t.cosoComponent},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'coso-principle', 'value': t.cosoPrinciple::VARCHAR},
             {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'mandate-id',     'value': t.mandateId}],
          'links': [
             {'rel': 'requirement', 'href': '#' || uuid_of(t.reqId),     'text': t.reqId},
             {'rel': 'mandate',     'href': '#' || uuid_of(t.mandateId),
              'text': t.authority || ' ' || t.section || '(' || t.subsection || ')'}],
          'target': {'type': 'objective-id', 'target-id': f.targetId,
                     'status': {'state': f.state, 'reason': f.reason}},
          'related-observations': list({'observation-uuid': fo.observationUuid})} AS entry
    FROM Finding f
    JOIN trace t                ON t.controlId   = f.controlId
    JOIN AssessmentRun a        ON a.controlId   = f.controlId
    JOIN FindingObservation fo  ON fo.findingUuid = f.uuid
   GROUP BY f.uuid, f.title, a.detail, f.controlId, f.targetId, f.state, f.reason,
            t.reqId, t.methodology, t.cosoComponent, t.cosoPrinciple,
            t.mandateId, t.authority, t.section, t.subsection),
-- back-matter is what the links above resolve against: the statute
-- subsections under test, and the requirements that discharge them.
resources AS (
            SELECT DISTINCT
                   {'uuid': uuid_of(mandateId),
                    'title': authority || ' ' || section || '(' || subsection || ')',
                    'description': obligation,
                    'props': [
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'authority',  'value': authority},
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'section',    'value': section},
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'subsection', 'value': subsection}]} AS entry
              FROM trace
  UNION ALL SELECT DISTINCT
                   {'uuid': uuid_of(reqId),
                    'title': reqId,
                    'description': reqText,
                    'props': [
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'coso-component', 'value': cosoComponent},
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'coso-principle', 'value': cosoPrinciple::VARCHAR},
                       {'ns': 'https://anaivebidder.com/ns/oscal', 'name': 'mandate-id',     'value': mandateId}]}
              FROM trace)
SELECT {
  'uuid': '11111111-1111-4111-8111-111111111111',
  'metadata': {
     'title': 'SOX 404 intercompany reconciliation - FY2026',
     'last-modified': (SELECT strftime(max(collected), '%Y-%m-%dT%H:%M:%SZ') FROM Observation),
     'version': '1.0', 'oscal-version': '1.1.2'},
  'import-ap': {'href': '#sox-404-icfr-assessment-plan'},
  'results': [{
     'uuid': '22222222-2222-4222-8222-222222222222',
     'title': 'Period-end intercompany control run',
     'description': 'Automated execution of the registered SQL procedures.',
     'start': (SELECT strftime(max(collected), '%Y-%m-%dT%H:%M:%SZ') FROM Observation),
     'reviewed-controls': {'control-selections': [
        {'include-controls': (SELECT list(DISTINCT {'control-id': lower(scfId)}) FROM obs)}]},
     'observations': (SELECT list(entry) FROM obs),
     'findings':     (SELECT list(entry) FROM fin)}],
  'back-matter': {'resources': (SELECT list(entry) FROM resources)}
  } AS "assessment-results"
) TO 'oscal-assessment-results.json' (FORMAT JSON, ARRAY false);
