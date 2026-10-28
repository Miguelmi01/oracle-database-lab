#!/usr/bin/env bash
# scripts/deployment/env/03-desplegar-oracle.sh
source scripts/deployment/env/00-config.sh

echo "== Verificando variables de entorno en config/.env =="
if [ -f config/.env ]; then
  source config/.env
  echo "Archivo config/.env cargado correctamente."
else
  echo "ERROR: No se encontro el archivo config/.env"
  exit 1
fi

echo "== Desplegando contenedor Oracle mediante Docker Compose =="
docker compose up -d

echo "== Estado de los contenedores =="
docker compose ps
