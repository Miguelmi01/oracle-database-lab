#!/usr/bin/env bash
# scripts/deployment/env/02-instalar-docker.sh
echo "== Verificacion de Docker Engine =="
if command -v docker > /dev/null 2>&1; then
  echo "Docker ya esta instalado:"
  docker --version
else
  echo "Docker NO esta instalado. Sigue la guia del laboratorio para instalarlo en WSL 2."
fi
