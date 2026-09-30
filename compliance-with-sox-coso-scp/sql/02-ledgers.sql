-- The operational side: one ledger table per legal entity, plus the
-- consolidation view that reads them as one. Rows are loaded by a seed.

-- ===== operational data ==============================================
-- A US parent, an Irish manufacturing subsidiary and a German
-- distribution subsidiary that trade with each other. Each one runs its
-- own ledger, in its own table, in its own functional currency -- which
-- is the situation the controls exist for. No table knows what the
-- others hold.
CREATE TABLE Entity (
  entityId VARCHAR, name VARCHAR, country VARCHAR, currency VARCHAR,
  ledgerTable VARCHAR);

INSERT INTO Entity VALUES
  ('US-PARENT', 'Northwind Holdings Inc.',      'US', 'USD', 'LedgerUsParent'),
  ('IE-MFG',    'Northwind Manufacturing Ltd.', 'IE', 'EUR', 'LedgerIeMfg'),
  ('DE-DIST',   'Northwind Distribution GmbH',  'DE', 'EUR', 'LedgerDeDist');

-- The three ledgers share a shape but not a table. One row per posted
-- leg: 'AR' is this entity's receivable on a sale to the counterparty,
-- 'AP' its payable on a purchase from it. A transaction is the pair --
-- one row here and one row in the counterparty's own table.
--
-- There is no entityId column: the table is the entity.
CREATE TABLE LedgerUsParent (
  entryId VARCHAR, icRefId VARCHAR, counterpartyId VARCHAR,
  leg VARCHAR, postingDate DATE, amountLocal DECIMAL(18,2), currency VARCHAR,
  fxRate DECIMAL(12,6), fxSource VARCHAR, fxAsOf TIMESTAMP,
  amountUsd DECIMAL(18,2), glAccount VARCHAR, postedBy VARCHAR);

CREATE TABLE LedgerIeMfg (
  entryId VARCHAR, icRefId VARCHAR, counterpartyId VARCHAR,
  leg VARCHAR, postingDate DATE, amountLocal DECIMAL(18,2), currency VARCHAR,
  fxRate DECIMAL(12,6), fxSource VARCHAR, fxAsOf TIMESTAMP,
  amountUsd DECIMAL(18,2), glAccount VARCHAR, postedBy VARCHAR);

CREATE TABLE LedgerDeDist (
  entryId VARCHAR, icRefId VARCHAR, counterpartyId VARCHAR,
  leg VARCHAR, postingDate DATE, amountLocal DECIMAL(18,2), currency VARCHAR,
  fxRate DECIMAL(12,6), fxSource VARCHAR, fxAsOf TIMESTAMP,
  amountUsd DECIMAL(18,2), glAccount VARCHAR, postedBy VARCHAR);

-- thing a control needs and the only place the entity is named.
CREATE VIEW IcLedgerEntry AS
            SELECT 'US-PARENT' AS entityId, * FROM LedgerUsParent
  UNION ALL SELECT 'IE-MFG',                * FROM LedgerIeMfg
  UNION ALL SELECT 'DE-DIST',               * FROM LedgerDeDist;
