-- Formatting, the rejection predicates, and the twelve procedures the
-- register names. Identical for five rows and for ten million.

-- ===== the check procedures ==========================================

-- Amounts are reported short: 10.00M rather than 10000000.00. A reconciliation
-- is read by eye, and a column of nine-digit decimals is the fastest way to
-- miss the one that matters.
-- Trailing zeros carry no information, so 5.00M reads as 5M and 1.20M as
-- 1.2M, while 1.44M keeps both digits. rtrim stops at the decimal point, so
-- the integer part is never touched: 10.00 loses ".00", not its zero.
CREATE MACRO trim0(s) AS (
  CASE WHEN contains(s, '.') THEN rtrim(rtrim(s, '0'), '.') ELSE s END);

CREATE MACRO money(x) AS (
  CASE WHEN x IS NULL              THEN NULL
       WHEN abs(x) >= 1000000000   THEN trim0(format('{:.2f}', x / 1000000000.0)) || 'B'
       WHEN abs(x) >= 1000000      THEN trim0(format('{:.2f}', x / 1000000.0)) || 'M'
       WHEN abs(x) >= 1000         THEN format('{:.0f}', x / 1000.0) || 'K'
       ELSE trim0(format('{:.2f}', x::DOUBLE)) END);

-- A stable UUID for a register identifier, so the OSCAL document can link a
-- finding to a requirement and a requirement to a statute subsection with
-- hrefs that resolve inside the document and do not move between runs.
-- md5 laid out as 8-4-4-4-12 with the version and variant nibbles forced.
CREATE MACRO uuid_of(seed) AS (
  substr(md5(seed),  1, 8) || '-' ||
  substr(md5(seed),  9, 4) || '-4' ||
  substr(md5(seed), 14, 3) || '-8' ||
  substr(md5(seed), 18, 3) || '-' ||
  substr(md5(seed), 21, 12));

-- Both legs of a reference, side by side. Every check below reads this.
CREATE MACRO ic_pairs() AS TABLE (
  SELECT icRefId,
         max(CASE WHEN leg = 'AR' THEN entityId  END) AS seller,
         max(CASE WHEN leg = 'AP' THEN entityId  END) AS buyer,
         max(CASE WHEN leg = 'AR' THEN amountUsd END) AS ar_usd,
         max(CASE WHEN leg = 'AP' THEN amountUsd END) AS ap_usd,
         max(CASE WHEN leg = 'AR' THEN postedBy  END) AS ar_posted_by,
         max(CASE WHEN leg = 'AP' THEN postedBy  END) AS ap_posted_by,
         count(*) FILTER (WHERE leg = 'AR') AS ar_legs,
         count(*) FILTER (WHERE leg = 'AP') AS ap_legs
    FROM IcLedgerEntry
   GROUP BY icRefId);

-- ===== the rejection conditions, one per EARS sentence ===============
-- Each EARS requirement is written in the unwanted-behaviour form: a
-- disjunction of everything that must hold, negated. Any one of them being
-- false rejects, so the default is rejection and compliance is what has to
-- be demonstrated. Defined once here rather than repeated inside every
-- procedure, so the sentence and the predicate cannot drift apart.
--
-- Note the IS NULL terms: an absent value is not a passing value. Without
-- them, a leg posted with no USD amount compares to NULL, and a NULL
-- comparison is not true, so the transaction would slip through unchecked.

-- REQ-301-C1. Reject unless both legs exist, both are translated, and the
-- two agree within 1 USD.
CREATE MACRO ic_rejected(ar_legs, ap_legs, ar_usd, ap_usd) AS (
  ar_legs = 0 OR ap_legs = 0
  OR ar_usd IS NULL OR ap_usd IS NULL
  OR abs(ar_usd - ap_usd) > 1.00);

-- REQ-302-C1. Refuse unless both posting identities are recorded and they
-- differ. An unrecorded identity cannot demonstrate separation of duties.
CREATE MACRO sod_refused(ar_posted_by, ap_posted_by) AS (
  ar_posted_by IS NULL OR ap_posted_by IS NULL
  OR ar_posted_by = ap_posted_by);

-- REQ-303-C1. Reject unless the translation can be recomputed from the row.
-- Parameters are not named `source`: it is reserved in the parser.
CREATE MACRO fx_rejected(rateValue, rateSource, rateAsOf) AS (
  rateValue IS NULL OR rateSource IS NULL OR rateAsOf IS NULL);

-- ===== EARS controls: invariants =====================================
-- Any row returned is a transaction the service would have rejected, so a
-- clean run returns nothing.

-- REQ-301-C1. The reason is carried rather than inferred: "nobody booked it",
-- "it was never translated" and "the two sides disagree" are different
-- findings with different remediations.
CREATE MACRO check_req_301() AS TABLE (
  SELECT icRefId, seller, buyer, ar_usd, ap_usd,
         coalesce(ar_usd, 0) - coalesce(ap_usd, 0) AS variance_usd,
         CASE WHEN ar_legs = 0                       THEN 'no seller leg recorded'
              WHEN ap_legs = 0                       THEN 'no buyer leg recorded'
              WHEN ar_usd IS NULL OR ap_usd IS NULL  THEN 'leg not translated to USD'
              ELSE 'legs differ beyond tolerance' END AS reason
    FROM ic_pairs()
   WHERE ic_rejected(ar_legs, ap_legs, ar_usd, ap_usd));

-- REQ-302-C1. Segregation of duties across the two entities. Only a
-- reference with two legs has an opposing posting to refuse.
CREATE MACRO check_req_302() AS TABLE (
  SELECT icRefId, seller, buyer, ar_posted_by, ap_posted_by,
         CASE WHEN ar_posted_by IS NULL OR ap_posted_by IS NULL
              THEN 'no posting identity recorded'
              ELSE 'both legs posted by one identity' END AS reason
    FROM ic_pairs()
   WHERE ar_legs > 0 AND ap_legs > 0
     AND sod_refused(ar_posted_by, ap_posted_by));

-- REQ-303-C1. The translation must be reproducible from the row itself.
-- Like REQ-301-C1, it carries which of its three conditions failed: a leg
-- with no rate, a leg with no source and a leg with no timestamp are three
-- different findings. The first two mean the amount cannot be recomputed at
-- all; the third means it can be recomputed but never verified against the
-- rate that was actually published.
CREATE MACRO check_req_303() AS TABLE (
  SELECT entryId, icRefId, entityId, leg, currency,
         CASE WHEN fxRate   IS NULL THEN 'no rate recorded'
              WHEN fxSource IS NULL THEN 'no rate source recorded'
              ELSE 'no rate timestamp recorded' END AS reason
    FROM IcLedgerEntry
   WHERE fx_rejected(fxRate, fxSource, fxAsOf));

-- ===== Gherkin controls: assertions ==================================
-- Each scenario names its case and carries its own expected answer, so it
-- reports a verdict rather than a list to interpret. They test the checker.

-- REQ-301-C2.
CREATE MACRO check_scenario_301() AS TABLE (
  WITH scenario(name, given_ref, expected) AS (
    VALUES ('both-legs-recorded-and-reconciled', 'IC-1001', 'compliant'),
           ('buyer-leg-never-recorded',          'IC-1002', 'non-compliant'),
           ('legs-differ-beyond-tolerance',      'IC-1003', 'non-compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN ic_rejected(p.ar_legs, p.ap_legs, p.ar_usd, p.ap_usd)
              THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN (CASE WHEN ic_rejected(p.ar_legs, p.ap_legs, p.ar_usd, p.ap_usd)
                         THEN 'non-compliant' ELSE 'compliant' END) = s.expected
              THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s JOIN ic_pairs() p ON p.icRefId = s.given_ref);

-- REQ-302-C2.
CREATE MACRO check_scenario_302() AS TABLE (
  WITH scenario(name, given_ref, expected) AS (
    VALUES ('two-identities-post-the-two-legs', 'IC-1001', 'compliant'),
           ('cross-period-pair-still-split',    'IC-1003', 'compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN sod_refused(p.ar_posted_by, p.ap_posted_by)
              THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN (CASE WHEN sod_refused(p.ar_posted_by, p.ap_posted_by)
                         THEN 'non-compliant' ELSE 'compliant' END) = s.expected
              THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s JOIN ic_pairs() p ON p.icRefId = s.given_ref);

-- REQ-303-C2. Named cases, like the other two: one leg that carries a
-- complete translation record and one that lost its timestamp, each
-- asserting the verdict the specification calls for.
CREATE MACRO check_scenario_303() AS TABLE (
  WITH scenario(name, given_entry, expected) AS (
    VALUES ('translation-is-reproducible', 'E-0002', 'compliant'),
           ('leg-posted-without-a-timestamp', 'E-0007', 'non-compliant'))
  SELECT s.name AS scenario, s.expected,
         CASE WHEN fx_rejected(l.fxRate, l.fxSource, l.fxAsOf)
              THEN 'non-compliant' ELSE 'compliant' END AS actual,
         CASE WHEN (CASE WHEN fx_rejected(l.fxRate, l.fxSource, l.fxAsOf)
                         THEN 'non-compliant' ELSE 'compliant' END) = s.expected
              THEN 'pass' ELSE 'FAIL' END AS result
    FROM scenario s JOIN IcLedgerEntry l ON l.entryId = s.given_entry);
