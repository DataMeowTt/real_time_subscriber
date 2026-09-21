-- Smoke test phần 2: đọc lại chỉ từ Paimon ($lake), tức dữ liệu đã được tiering.
-- Mỗi truy vấn có cột nhãn để script đối chiếu theo dòng: | <nhãn> | <số đếm> |
SET 'sql-client.execution.result-mode' = 'tableau';
SET 'execution.runtime-mode' = 'batch';

-- Server Fluss không gửi credential S3 cho client, nên phía Flink phải tự khai báo
-- để đọc được Paimon ($lake). Giá trị khớp S3_ACCESS_KEY/S3_SECRET_KEY trong .env.
CREATE CATALOG fluss_catalog WITH (
  'type' = 'fluss',
  'bootstrap.servers' = 'coordinator-server:9123',
  'paimon.s3.access-key' = 'rustfsadmin',
  'paimon.s3.secret-key' = 'rustfsadmin'
);
USE CATALOG fluss_catalog;
USE smoke;

-- Kỳ vọng: 3 sau khi tiering đã commit
SELECT 'paimon_only_events' AS k, COUNT(*) AS v FROM `smoke_events$lake`;

-- Kỳ vọng: 2 (PK table đã khử trùng theo msisdn)
SELECT 'paimon_only_profiles' AS k, COUNT(*) AS v FROM `smoke_profile$lake`;
