#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

mkdir -p lib
jar="lib/paimon-s3-${PAIMON_VERSION}.jar"
if [[ -s "$jar" ]]; then
  echo "đã có $jar"
  exit 0
fi
curl -fL -o "$jar" \
  "https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-s3/${PAIMON_VERSION}/paimon-s3-${PAIMON_VERSION}.jar"
echo "đã tải $jar"
