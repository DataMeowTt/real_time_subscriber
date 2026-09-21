#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

TIERING_TIMEOUT_SEC="${TIERING_TIMEOUT_SEC:-180}"

RUN_ID="${RUN_ID:-$(date +%s)}"
mkdir -p smoke/.run
for f in 01_write.sql 02_read.sql; do
  sed -e "s/smoke_profile/smoke_profile_${RUN_ID}/g" \
      -e "s/smoke_events/smoke_events_${RUN_ID}/g" "smoke/$f" > "smoke/.run/$f"
done
echo "RUN_ID=${RUN_ID} (bảng: smoke_profile_${RUN_ID}, smoke_events_${RUN_ID})"

SQL_TIMEOUT_SEC="${SQL_TIMEOUT_SEC:-90}"
sql() { docker compose exec -T jobmanager timeout "$SQL_TIMEOUT_SEC" /opt/flink/bin/sql-client.sh -f "/opt/smoke/.run/$1"; }

echo "==> [1/6] Tải jar"
scripts/download-jars.sh

echo "==> [2/6] Dựng stack"
docker compose up -d --wait --wait-timeout 300 jobmanager taskmanager coordinator-server tablet-server
docker compose ps

echo "==> [3/6] Chạy tiering service (Flink job)"
if docker compose exec -T jobmanager /opt/flink/bin/flink list 2>/dev/null | grep -qi "tiering"; then
  echo "tiering service đã chạy"
else
  docker compose exec -T jobmanager /opt/flink/bin/flink run -d \
    "/opt/flink/opt/fluss-flink-tiering-${FLUSS_VERSION}.jar" \
    --fluss.bootstrap.servers coordinator-server:9123 \
    --datalake.format paimon \
    --datalake.paimon.metastore filesystem \
    --datalake.paimon.warehouse s3://fluss/paimon \
    --datalake.paimon.s3.endpoint http://rustfs:9000 \
    --datalake.paimon.s3.access.key "${S3_ACCESS_KEY}" \
    --datalake.paimon.s3.secret.key "${S3_SECRET_KEY}" \
    --datalake.paimon.s3.path.style.access true
fi

echo "==> [4/6] Ghi dữ liệu vào Fluss"
out=$(sql 01_write.sql 2>&1) || { echo "$out"; exit 1; }
echo "$out"
grep -q "PLAN_C" <<<"$out" || { echo "FAIL: PK upsert không trả về PLAN_C"; exit 1; }

echo "==> [5/6] Chờ tiering sang Paimon (tối đa ${TIERING_TIMEOUT_SEC}s)"
deadline=$((SECONDS + TIERING_TIMEOUT_SEC))
attempt=0
until out=$(sql 02_read.sql 2>&1) \
      && grep -Eq "paimon_only_events *\| *3 *\|" <<<"$out" \
      && grep -Eq "paimon_only_profiles *\| *2 *\|" <<<"$out"; do
  attempt=$((attempt + 1))
  echo "  lần thử ${attempt} chưa đạt ($((deadline - SECONDS))s còn lại):"
  grep -E "paimon_only|ERROR|Exception|Reason|Missing|timeout" <<<"$out" | head -5 | sed 's/^/    /' || true
  if (( SECONDS >= deadline )); then
    echo "$out"
    echo "FAIL: quá thời gian chờ tiering"
    exit 1
  fi
  sleep 10
done

echo "==> [6/6] Kết quả đọc từ Paimon"
echo "$out"
echo "OK: stack B chạy được (Fluss -> tiering -> Paimon)"
