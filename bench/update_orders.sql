-- pgbench custom script: random UPDATE on orders table
-- Simulates high-frequency order status changes (write-heavy workload)
UPDATE orders
SET status = (ARRAY['PENDING','PAID','SHIPPED','CANCELLED'])[floor(random()*4+1)]
WHERE id = (floor(random() * 1000000) + 1)::bigint;
