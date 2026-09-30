-- =====================================================================
-- A group-sized intercompany population.
--
-- Generates `trade_count` trades (default 5,000,000) on top of the three
-- named exemplars from the post, which are loaded first so the Gherkin
-- scenarios still have the references they name.
--
-- Override the volume by setting the variable before this runs:
--   SET VARIABLE trade_count = 250000;
-- run.sh does exactly that from $TRADES.
--
-- 5% of trades carry an issue, split across four causes. The split is
-- deterministic - bucket = i % 1000 - so the same volume always produces
-- the same population, and the counts are exact rather than sampled.
--
--   bucket  0-19   2.0%   the buyer never records its leg
--   bucket 20-37   1.8%   the buyer records a smaller amount (timing)
--   bucket 38-44   0.7%   one identity posts both legs
--   bucket 45-49   0.5%   the buyer's leg carries no translation record
--   bucket 50-999 95.0%   clean
-- =====================================================================

SET VARIABLE trade_count = coalesce(getvariable('trade_count'), 5000000);

-- The three exemplars keep their meaning: check_scenario_301 and _302 bind
-- to IC-1001..IC-1003 by name.
.read sql/seed-sample.sql

-- One row per trade, with both sides resolved. Dropped once the legs are out.
CREATE TABLE GenTrade AS
WITH ent(entityId, ccy, rate, uid) AS (
       VALUES ('US-PARENT', 'USD', 1.000000, 'U-US'),
              ('IE-MFG',    'EUR', 1.250000, 'U-IE'),
              ('DE-DIST',   'EUR', 1.250000, 'U-DE')),
     pair(pairNo, seller, buyer) AS (
       VALUES (0, 'US-PARENT', 'IE-MFG'),  (1, 'US-PARENT', 'DE-DIST'),
              (2, 'IE-MFG',    'US-PARENT'), (3, 'IE-MFG',  'DE-DIST'),
              (4, 'DE-DIST',   'US-PARENT'), (5, 'DE-DIST', 'IE-MFG')),
     base AS (
       SELECT i,
              'IC-' || (1000000 + i)::VARCHAR                   AS icRefId,
              i % 1000                                          AS bucket,
              p.seller, p.buyer,
              s.ccy  AS sellerCcy,  s.rate AS sellerRate,
              b.ccy  AS buyerCcy,   b.rate AS buyerRate,
              DATE '2026-01-02' + CAST(i % 360 AS INTEGER)      AS postingDate,
              CAST(10000 + (i % 990) * 1000 AS DECIMAL(18,2))   AS sellerLocal,
              -- // is integer division; i / 7 would be a DOUBLE, and lpad
              -- truncates, so '0.0' came out as '0.'
              s.uid || '-' || lpad(((i //  7) % 20)::VARCHAR, 2, '0') AS sellerBy,
              b.uid || '-' || lpad(((i // 11) % 20)::VARCHAR, 2, '0') AS buyerByRaw
         FROM range(1, getvariable('trade_count') + 1) t(i)
         JOIN pair p ON p.pairNo   = i % 6
         JOIN ent  s ON s.entityId = p.seller
         JOIN ent  b ON b.entityId = p.buyer)
SELECT icRefId, bucket, seller, buyer, postingDate,
       sellerCcy, sellerRate, sellerLocal, sellerBy,
       round(sellerLocal * sellerRate, 2) AS sellerUsd,
       buyerCcy, buyerRate,
       -- a timing break: the buyer books 96% of what the seller invoiced
       CASE WHEN bucket BETWEEN 20 AND 37
            THEN round(round(sellerLocal * sellerRate, 2) * 0.96, 2)
            ELSE round(sellerLocal * sellerRate, 2) END AS buyerUsd,
       -- a segregation-of-duties breach: the seller's identity posts both
       CASE WHEN bucket BETWEEN 38 AND 44 THEN sellerBy ELSE buyerByRaw END AS buyerBy,
       'EG-' || i::VARCHAR AS entrySeq
  FROM base;

-- Every leg, in one shape, before being split across the three ledgers.
CREATE TABLE GenLeg AS
            SELECT seller AS entityId, entrySeq || 'A' AS entryId, icRefId,
                   buyer AS counterpartyId, 'AR' AS leg, postingDate,
                   sellerLocal AS amountLocal, sellerCcy AS currency,
                   sellerRate AS fxRate, 'ECB' AS fxSource,
                   postingDate::TIMESTAMP + INTERVAL 16 HOUR AS fxAsOf,
                   sellerUsd AS amountUsd, '1310' AS glAccount, sellerBy AS postedBy
              FROM GenTrade
  UNION ALL SELECT buyer, entrySeq || 'B', icRefId,
                   seller, 'AP', postingDate,
                   round(buyerUsd / buyerRate, 2), buyerCcy,
                   -- 0.5%: the leg is posted with no translation record at all
                   CASE WHEN bucket BETWEEN 45 AND 49 THEN NULL ELSE buyerRate END,
                   CASE WHEN bucket BETWEEN 45 AND 49 THEN NULL ELSE 'ECB' END,
                   CASE WHEN bucket BETWEEN 45 AND 49 THEN NULL
                        ELSE postingDate::TIMESTAMP + INTERVAL 16 HOUR END,
                   buyerUsd, '2310', buyerBy
              FROM GenTrade
             -- 2.0%: the buyer never records its leg, so no row is emitted
             WHERE bucket > 19;

INSERT INTO LedgerUsParent
SELECT entryId, icRefId, counterpartyId, leg, postingDate, amountLocal, currency,
       fxRate, fxSource, fxAsOf, amountUsd, glAccount, postedBy
  FROM GenLeg WHERE entityId = 'US-PARENT';

INSERT INTO LedgerIeMfg
SELECT entryId, icRefId, counterpartyId, leg, postingDate, amountLocal, currency,
       fxRate, fxSource, fxAsOf, amountUsd, glAccount, postedBy
  FROM GenLeg WHERE entityId = 'IE-MFG';

INSERT INTO LedgerDeDist
SELECT entryId, icRefId, counterpartyId, leg, postingDate, amountLocal, currency,
       fxRate, fxSource, fxAsOf, amountUsd, glAccount, postedBy
  FROM GenLeg WHERE entityId = 'DE-DIST';

DROP TABLE GenLeg;
DROP TABLE GenTrade;

INSERT INTO RunPhase VALUES ('seeded', get_current_timestamp());
