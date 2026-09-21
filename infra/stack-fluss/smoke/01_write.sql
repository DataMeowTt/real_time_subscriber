-- Smoke test phần 1: catalog, PK table (upsert + point lookup), Log table (append).
-- Cả hai bảng bật datalake để tiering service đẩy sang Paimon.
SET 'sql-client.execution.result-mode' = 'tableau';
SET 'execution.runtime-mode' = 'batch';
-- Bắt INSERT chạy đồng bộ, nếu không SELECT phía dưới có thể chạy trước khi dữ liệu được ghi.
SET 'table.dml-sync' = 'true';

CREATE CATALOG fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'coordinator-server:9123'
);
USE CATALOG fluss_catalog;
CREATE DATABASE IF NOT EXISTS smoke;
USE smoke;

CREATE TABLE IF NOT EXISTS smoke_profile (
  msisdn STRING,
  plan_code STRING,
  PRIMARY KEY (msisdn) NOT ENFORCED
) WITH (
  'bucket.num' = '4',
  'table.datalake.enabled' = 'true',
  'table.datalake.freshness' = '30s'
);

CREATE TABLE IF NOT EXISTS smoke_events (
  event_id STRING,
  msisdn STRING,
  data_bytes BIGINT,
  event_ts TIMESTAMP(3)
) WITH (
  'bucket.num' = '4',
  'bucket.key' = 'msisdn',
  'table.datalake.enabled' = 'true',
  'table.datalake.freshness' = '30s'
);

-- Hai INSERT riêng để thứ tự ghi cùng một khóa là xác định.
INSERT INTO smoke_profile VALUES
  ('84000000001', 'PLAN_A'),
  ('84000000002', 'PLAN_B');
INSERT INTO smoke_profile VALUES
  ('84000000001', 'PLAN_C');

INSERT INTO smoke_events VALUES
  ('e1', '84000000001', 100, TIMESTAMP '2026-09-21 10:00:00'),
  ('e2', '84000000001', 200, TIMESTAMP '2026-09-21 10:00:01'),
  ('e3', '84000000002', 300, TIMESTAMP '2026-09-21 10:00:02');

-- Kỳ vọng: 84000000001 -> PLAN_C (bản ghi sau ghi đè bản ghi trước).
SELECT * FROM smoke_profile WHERE msisdn = '84000000001';
