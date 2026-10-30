#!/usr/bin/env bash
# scripts/deployment/env/09-verificar-java-sqlcl.sh
source scripts/deployment/env/00-config.sh

echo "== Java =="
java -version
echo "$JAVA_HOME"

echo "== SQLcl =="
sql -v
