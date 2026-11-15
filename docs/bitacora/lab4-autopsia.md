# Autopsia de la Arquitectura Oracle Database — Laboratorio 4

## 1. Identidad de la instancia y de la base de datos
* **Instancia:** `FREE` ejecutándose en el contenedor `2a83b5d193c1` (versión `23.26.3.0.0`, estado `OPEN`, `DATABASE_STATUS = ACTIVE`).
* **Base de datos:** `FREE` (`DBID = 1509902213`), arquitectura multitenant (`CDB = YES`), modo `ARCHIVELOG`, `FORCE_LOGGING = YES`, `FLASHBACK_ON = NO`, rol `PRIMARY` y `OPEN_MODE = READ WRITE`.
* **Contenedores (PDBs):**
  * `CDB$ROOT` (`CON_ID = 1`): `READ WRITE` (0 MB de datos de usuario propios).
  * `PDB$SEED` (`CON_ID = 2`): `READ ONLY` (810 MB, plantilla inmutable para clonar nuevas PDBs).
  * `FREEPDB1` (`CON_ID = 3`): `READ WRITE` (1442 MB, PDB operativa donde residen los esquemas de negocio).

## 2. Memoria: SGA y PGA
* **SGA (System Global Area — compartida):** Tamaño máximo `1529 MB` (`SGA_TARGET = 1610612736` bytes):
  * `Buffer Cache`: `1056 MB` (redimensionable).
  * `Shared Pool`: `432 MB` (redimensionable).
  * `Large Pool`: `16 MB` (redimensionable).
  * `Fixed SGA`: `5 MB` y `Redo Buffers`: `4 MB` (no redimensionables).
  * Memoria libre disponible en SGA: `16 MB`.
* **PGA (Program Global Area — privada por proceso servidor):**
  * `PGA_AGGREGATE_TARGET`: `512 MB` (`536870912` bytes).
  * Memoria PGA total asignada en el momento de la captura: `391 MB` (pico máximo alcanzado: `457 MB`).

## 3. Procesos en segundo plano y servidores
* **Procesos en segundo plano (background):** `85` procesos activos en la instancia, entre los que destacan los obligatorios y de archivo: `PMON`, `SMON`, `DBW0`, `LGWR`, `CKPT`, `MMON`, `MMNL`, `RECO`, `LREG`, `PSP0`, `VKTM`, `DBRM`, `ARC0` y `ARC1`.
* **Procesos de servidor / otros:** `7` procesos atendiendo sesiones activas.

## 4. Almacenamiento físico (archivos de BD y relacionados)
* **Archivos que forman la base de datos:**
  * `16` **Datafiles** (`3984 MB` en total, tamaño de bloque `DB_BLOCK_SIZE = 8192` bytes).
  * `2` **Control files** multiplexados (`36 MB` en total).
  * `3` **Online Redo Log** (`600 MB` en total).
* **Archivos relacionados (no son datos de usuario pero son críticos para arranque/recuperación):**
  * `SPFILE`: `/opt/oracle/product/26ai/dbhomeFree/dbs/spfileFREE.ora`.
  * `3` **Tempfiles** (`60 MB` en total).
  * `4` **Archived Redo Logs** en disco (`362 MB` en total).

## 5. Almacenamiento lógico, índices y seguridad
* **Tablespaces:** En `CDB$ROOT` destacan `SYSTEM` (1057 MB) y `SYSAUX` (635 MB). En `FREEPDB1` residen los 5 tablespaces de negocio creados en el laboratorio (`TBS_ACADEMIA` al 2,2 % de uso con 22 MB; `TBS_CLINICA`, `TBS_FINTECH`, `TBS_LOGISTICA` y `TBS_RETAIL` al 0,6 % con 6 MB cada uno), sin alertas de saturación.
* **Segmentos e índices:** Todos los índices de los 5 esquemas de negocio (`ADMIN_ACADEMIA`, `ADMIN_CLINICA`, `ADMIN_FINTECH`, `ADMIN_LOGISTICA`, `ADMIN_RETAIL`) están en estado `VALID` (`NO_VALIDOS = 0`).
* **Seguridad:** Ninguna cuenta local (`COM = NO`) posee el rol `DBA`; únicamente las cuentas internas mantenidas por Oracle disponen de él, y los usuarios `ADMIN_*` operan sin contraseña (`NO AUTHENTICATION`) tras la migración `V003`.

## 6. Red y parámetros no por defecto
* **Servicios registrados en el listener:** `free`, `freeXDB` (`CON_ID = 1`) y `freepdb1` (`CON_ID = 3`), además de los servicios internos `SYS$BACKGROUND` y `SYS$USERS`.
* **Parámetros modificados respecto al valor por defecto:** `compatible = 23.6.0`, `db_block_size = 8192`, `db_name = FREE`, `enable_pluggable_database = TRUE`, `open_cursors = 300`, `pga_aggregate_target = 512M`, `processes = 200`, `remote_login_passwordfile = EXCLUSIVE`, `sga_target = 1536M` y `undo_tablespace = UNDOTBS1`.

## 7. Salud de la instancia (Alert Log — últimas 24 h)
Se registraron `8` entradas `ORA-` en las últimas 24 horas, todas esperadas y justificadas por las pruebas del laboratorio:
* `ORA-00800` (6 ocurrencias): aviso benigno de prioridad de procesos (`VKTM`/`LMS`) al arrancar Oracle dentro de un contenedor Docker sin privilegios `CAP_SYS_NICE`.
* `ORA-65025` (1 ocurrencia): intento de operación sobre una PDB (`FREEPDB1`) mientras estaba cerrada (`MOUNTED`) durante los ejercicios de ciclo de vida de contenedores.
* `ORA-00959` (1 ocurrencia): referencia a un tablespace inexistente tras la limpieza de `TBS_LAB4` o durante las comprobaciones de almacenamiento.
