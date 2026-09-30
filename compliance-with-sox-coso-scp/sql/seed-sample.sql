-- The seven-row worked example from the post.

-- The US parent: a sale to Ireland, and a purchase from Germany booked
-- in the next period.
INSERT INTO LedgerUsParent VALUES
  ('E-0001', 'IC-1001', 'IE-MFG',  'AR', DATE '2026-11-30',
   5000000.00, 'USD', 1.000000, 'ECB', TIMESTAMP '2026-11-30 16:00:00', 5000000.00, '1310', 'U-ALEX'),
  ('E-0005', 'IC-1003', 'DE-DIST', 'AP', DATE '2027-01-04',
   1440000.00, 'USD', 1.000000, 'ECB', TIMESTAMP '2027-01-04 16:00:00', 1440000.00, '2310', 'U-ALEX'),
  -- IC-1004: a second sale to Germany. This leg is complete; its
  -- counterpart is the one that loses its rate timestamp.
  ('E-0006', 'IC-1004', 'DE-DIST', 'AR', DATE '2026-12-10',
   2000000.00, 'USD', 1.000000, 'ECB', TIMESTAMP '2026-12-10 16:00:00', 2000000.00, '1310', 'U-ALEX');

-- Ireland: the purchase from the parent, and a 10m USD sale to Germany.
INSERT INTO LedgerIeMfg VALUES
  ('E-0002', 'IC-1001', 'US-PARENT', 'AP', DATE '2026-11-30',
   4000000.00, 'EUR', 1.250000, 'ECB', TIMESTAMP '2026-11-30 16:00:00', 5000000.00, '2310', 'U-SIOBHAN'),
  ('E-0003', 'IC-1002', 'DE-DIST',   'AR', DATE '2026-12-18',
   8000000.00, 'EUR', 1.250000, 'ECB', TIMESTAMP '2026-12-18 16:00:00', 10000000.00, '1310', 'U-SIOBHAN');

-- Germany: a sale to the parent, and nothing at all for IC-1002. That
-- absent row is the material misstatement, and it is absent here rather
-- than wrong somewhere -- no query against this table can see it.
INSERT INTO LedgerDeDist VALUES
  ('E-0004', 'IC-1003', 'US-PARENT', 'AR', DATE '2026-12-29',
   1200000.00, 'EUR', 1.250000, 'ECB', TIMESTAMP '2026-12-29 16:00:00', 1500000.00, '1310', 'U-KLAUS'),
  -- IC-1004 reconciles: 1.6m EUR at 1.25 is the 2m USD the parent booked.
  -- What it lacks is fxAsOf, so nobody can say which rate applied when.
  -- REQ-301 and REQ-302 pass on this pair; REQ-303 rejects the leg.
  ('E-0007', 'IC-1004', 'US-PARENT', 'AP', DATE '2026-12-10',
   1600000.00, 'EUR', 1.250000, 'ECB', NULL, 2000000.00, '2310', 'U-KLAUS');

-- Consolidation reads the three ledgers as one. This view is the first

INSERT INTO RunPhase VALUES ('seeded', get_current_timestamp());
