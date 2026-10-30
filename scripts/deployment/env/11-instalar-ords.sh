#!/usr/bin/env bash
# scripts/deployment/env/11-instalar-ords.sh
source scripts/deployment/env/00-config.sh
set -a; source config/.env; set +a

ords --config "$ORDS_CONFIG" install \
  --db-pool default \
  --admin-user SYS \
  --db-hostname localhost \
  --db-port 1521 \
  --db-servicename "$SERVICE_PDB" \
  --feature-db-api true \
  --feature-sdw true \
  --password-stdin <<ORDS_PWDS
$ORACLE_PWD
$ORDS_PUBLIC_PWD
ORDS_PWDS
