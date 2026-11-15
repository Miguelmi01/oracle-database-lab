# Kit de scripts · Labs 4 y 5 v3 (oracle-database-lab)

Copia estos archivos sobre el repositorio `oracle-database-lab` del alumno (o de un repositorio plantilla), respetando las rutas. Sustituye a los kits v1 y v2.

| Ruta | Laboratorio | Qué es |
|---|---|---|
| `scripts/ops/` | Labs 4 y 5 | Copia y restauración en frío, sonda de disponibilidad, `sysdba.sh`, `ro.sh` y `grafico-indice.sh` (mapa de ocupación de las hojas de un índice) |
| `scripts/lab4/` | Lab 4, Partes A–O | 01–16: diagnóstico, correcciones del Lab 3, instancia, arranque, parámetros, memoria y parse/PGA, procesos, contenedores, autopsia de archivos, anatomía del bloque, capacidad y coste, filas migradas/encadenadas, autopsia de la instancia y verificación final |
| `scripts/lab5/` | Lab 5, Partes A–Q | 01–07: banco TiendaSur, `lab_tools.medir`, anatomía y tipos de índice, clustering factor y punto de equilibrio, sargabilidad, protocolo de diseño y coste DML, divisiones de hoja y patrón cola. 08–16: SCN, control files, redo, ARCHIVELOG/FRA, undo, LGWR/DBWn, simulacros A–D, healthcheck y verificación final |
| `scripts/deployment/env/` | Lab 4 (y Lab 5) | `05` y `08` v2, sin el puerto 8181 ni contraseñas en la línea de comandos. `00-config.sh` incluye EVID_LAB5 |
| `database/migrations/V002`–`V005` | Labs 4 y 5 | V002 datos demo, V003 cuentas sin contraseña, V004 banco TiendaSur (100 000 clientes, 1 000 000 pedidos), V005 diseño de índices justificado |
| `config/.env.example` | Lab 4, Parte B | Plantilla sin valores. El `.env` real nunca se versiona |

No incluye `config/.env`, `backups/` ni evidencias: cada alumno genera los suyos.

Probado de principio a fin, partiendo del estado del Lab 3 más este kit, sobre Oracle AI Database 26ai Free 23.26.3 con la imagen oficial `container-registry.oracle.com/database/free:latest`. Las dos verificaciones finales (`16-verificacion-final.sh`) terminan en «TODO OK».

Disco: el Lab 5 necesita unos 8 GB libres (TiendaSur + FRA de 4 GB).
