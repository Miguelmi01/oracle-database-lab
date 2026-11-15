# Respuestas de Comprobación y Examen — Laboratorio 4

## 8. Preguntas de comprobación

### 8.1. Respaldo y diagnóstico (Parte A)
1. **Consistencia de la copia en frío:** Es consistente porque se realizó tras un `SHUTDOWN IMMEDIATE` (`00-backup-lab3-final.script.log`), con todos los datafiles, control files y online redo logs cerrados al mismo SCN sin transacciones activas. Si se copiaran los archivos a nivel de sistema operativo con la base abierta sin modo `BEGIN BACKUP` / RMAN, los bloques estarían en distintos SCN (*fuzzy backups*) y la restauración fallaría al arrancar.
2. **`manifiesto.txt` y `SHA256SUMS`:** `manifiesto.txt` documenta la metadata del respaldo (marca temporal, versión, archivos incluidos) y `SHA256SUMS` guarda los resúmenes criptográficos de cada fichero. `restaurar-estado.sh` verifica primero `sha256sum -c SHA256SUMS` antes de sobrescribir ningún archivo de producción para evitar restaurar un backup corrupto.
3. **RPO y RTO:** En nuestro respaldo en frío (`backups/20261115T210033Z_lab3-final`), el **RPO** equivale al intervalo transcurrido desde el instante de la copia (cualquier cambio posterior sin archivelogs aplicados se perdería, RPO > 0), mientras que el **RTO** es el tiempo que tarda `restaurar-estado.sh` en detener el contenedor, copiar los ~4 GB del backup y levantar la instancia (unos pocos minutos).

### 8.1.1. Correcciones del Lab 3 (Partes C, D)
4. **Ubicación errónea de datafiles en V000:** Oracle creó los datafiles `TBS_*` fuera de la carpeta de la PDB (`/opt/oracle/oradata/FREE/FREEPDB1/`) porque se indicaron rutas relativas/por defecto sin `DB_CREATE_FILE_DEST` ni `PDB_FILE_NAME_CONVERT` configurado (`01-diagnostico-inicial.log` y `03-reubicar-datafiles.log`). Fijar `DB_CREATE_FILE_DEST = '/opt/oracle/oradata'` (OMF) habría colocado automáticamente cada datafile dentro de su subdirectorio de PDB.
5. **Por qué `ALTER TABLESPACE ... RENAME DATAFILE` no basta:** Esa sentencia únicamente actualiza la ruta del archivo en el control file y en el diccionario de datos; no mueve los bytes en el disco. Antes hay que poner el tablespace `OFFLINE` y copiar/mover físicamente el `.dbf` en el sistema operativo (`03-reubicar-datafiles.log`).
6. **Inmutabilidad de `V000` y `NO AUTHENTICATION` en `V003`:** Las migraciones ya aplicadas (`V000`) nunca se editan porque romperían el historial y el checksum de despliegue en entornos ya inicializados; por eso se crea `V003` (`04-V003__cuentas_esquema_sin_password.spool.log`). Usar `ALTER USER ... NO AUTHENTICATION` impide el inicio de sesión directo incluso si alguien conociera las contraseñas antiguas expuestas en el historial de Git.
7. **Prueba de persistencia:** Borrar el contenedor (`docker rm -f`) y volver a crearlo sobre el volumen demuestra que el estado de la base de datos vive en `/opt/oracle/oradata` y no en la capa efímera del contenedor (`03-prueba-persistencia.log`). Se ejecuta después de reubicar los datafiles porque, de haber quedado dentro del sistema de archivos del contenedor fuera del volumen, se habrían perdido al destruirlo.

### 8.1.2. Instancia, arranque y parámetros (Partes E, F)
8. **Instancia vs. Base de datos (`05-instancia-y-base.spool.log` y `15-autopsia-instancia.spool.log`):**
   * *Instancia (volátil):* `INSTANCE_NAME = FREE`, `SGA_TARGET = 1536 MB` (`1610612736` B) y `85` procesos en segundo plano (`PMON`, `SMON`, `DBW0`, `LGWR`, `CKPT`).
   * *Base de datos (persistente en disco):* `DBID = 1509902213`, `LOG_MODE = ARCHIVELOG` y sus `16` datafiles (`3984 MB`), `2` control files y `3` online redo logs.
9. **Etapas de arranque (`06-arranque-por-etapas.log`):**
   * `NOMOUNT`: lee el `SPFILE` (`spfileFREE.ora`), reserva la SGA y arranca los procesos de fondo (si intentas consultar vistas del control file aquí da `ORA-01507: database not mounted`).
   * `MOUNT`: lee los `control_files` para localizar datafiles y redo logs (consultar tablas del diccionario aquí da `ORA-01219: database or pluggable database not open`).
   * `OPEN`: abre los datafiles y redo logs dejando la BD operativa (`READ WRITE`).
10. **`V$PARAMETER` vs. `V$SPPARAMETER` (`07-parametros-lectura.spool.log`):** `V$PARAMETER` muestra el valor efectivo vigente en la memoria de la instancia, mientras que `V$SPPARAMETER` refleja lo que está escrito en el fichero binario `SPFILE` en disco (con `ISSPECIFIED = TRUE/FALSE`). Tras ejecutar `ALTER SYSTEM RESET db_files SCOPE=SPFILE`, `ISSPECIFIED` pasó a `FALSE` en `V$SPPARAMETER`.
11. **`PROCESSES` y cambio en memoria:** Aunque `V$PARAMETER` muestre un parámetro o se intente `SCOPE=MEMORY`, `PROCESSES` dimensiona estructuras estáticas de la SGA (tablas de procesos y sesiones) al arrancar la instancia en `NOMOUNT`, por lo que `ISSYS_MODIFIABLE = FALSE` y requiere `SCOPE=SPFILE` y reinicio.

### 8.1.3. Memoria y procesos (Partes G, H)
12. **Modelo de gestión de memoria (`08-memoria.spool.log` y `15-autopsia-instancia.spool.log`):** Usa **ASMM (Automatic Shared Memory Management)** combinado con gestión automática de PGA: `MEMORY_TARGET = 0`, `SGA_TARGET = 1536M` (con `DB_CACHE_SIZE = 0` y `SHARED_POOL_SIZE = 0` para que Oracle ajuste dinámicamente los pools) y `PGA_AGGREGATE_TARGET = 512M`.
13. **Experimento de Buffer Cache (`08-memoria.spool.log`):** Tras `ALTER SYSTEM FLUSH BUFFER_CACHE`, la primera ejecución del recorrido lee los bloques desde disco (`physical reads` altas y tasa de acierto baja); la segunda ejecución encuentra los bloques ya cacheados en el Buffer Cache (`physical reads = 0`, todas `consistent gets` / lecturas lógicas en memoria y tasa de acierto cercana al 100 %).
14. **Literales vs. Bind Variables (`08-memoria.spool.log`):** Con literales (`WHERE id = 1`, `2`, `3`...), cada sentencia genera un `SQL_ID` distinto en `V$SQL`, provocando tantos *hard parses* como ejecuciones y saturando la Shared Pool. Con variables de enlace (`WHERE id = :b1`), todas las ejecuciones comparten un único cursor en `V$SQL` (`1` *hard parse* y el resto *soft parses*).
15. **SPID de `LGWR` en `V$PROCESS` vs. `/proc` y `docker top` (`09-procesos.spool.log`):** El `SPID` de `LGWR` en `V$PROCESS` coincide exactamente con el PID del proceso `ora_lgwr_FREE` dentro del espacio de nombres de procesos del contenedor (`/proc/<SPID>`). `docker top` se ejecuta desde el host Linux y muestra el PID traducido en el namespace raíz del anfitrión.

### 8.1.4. Contenedores y diccionario (Parte I)
16. **16 datafiles en raíz vs. 9 en `FREEPDB1` (`10-diccionario.spool.log`):** Desde `CDB$ROOT`, `CDB_DATA_FILES` muestra todos los datafiles de todos los contenedores abiertos (`CDB$ROOT` + `PDB$SEED` + `FREEPDB1` = 16 archivos), mientras que al cambiar a `FREEPDB1`, `DBA_DATA_FILES` filtra únicamente los 9 datafiles locales de esa PDB (`SYSTEM`, `SYSAUX`, `USERS`, `UNDOTBS1` y los 5 `TBS_*`).
17. **`ORA-00942` en `LAB4_ANALISTA`:** Oracle lanza `ORA-00942: table or view does not exist` en lugar de `ORA-01031: insufficient privileges` cuando un usuario intenta consultar un objeto sobre el que no tiene ningún privilegio `SELECT` ni sinónimo visible, evitando así filtrar información sobre la existencia de objetos del diccionario.
18. **`C##LAB4_AUDITOR` vs. `C##OPS_RO`:** Ambos son usuarios comunes en `CDB$ROOT`, pero `C##LAB4_AUDITOR` solo tenía `CREATE SESSION` (sin acceso al diccionario de las PDBs), mientras que `C##OPS_RO` tiene `SELECT ANY DICTIONARY` y `SELECT_CATALOG_ROLE` con `CONTAINER=ALL`. Se igualarían otorgando `GRANT SELECT ANY DICTIONARY, SELECT_CATALOG_ROLE TO C##LAB4_AUDITOR CONTAINER=ALL;`.
19. **`GRANT READ ANY TABLE ON SCHEMA` (23ai):** Permite dar acceso de solo lectura (sin posibilidad de `SELECT FOR UPDATE` bloqueante) a todas las tablas actuales y futuras de un esquema en una sola sentencia, evitando mantener permisos tabla por tabla; su riesgo es que cualquier tabla nueva creada en ese esquema queda expuesta automáticamente.
20. **`COMMON_USER_PREFIX = C##`:** Obliga a que todo usuario o rol común creado en `CDB$ROOT` comience por `C##` (`10-ciclo-vida-pdb.spool.log`); intentar crear un usuario sin ese prefijo en la raíz devuelve `ORA-65096: invalid common user or role name`.

### 8.1.5. Archivos (Parte J)
21. **Clasificación de archivos (`11-archivos.spool.log` y `15-autopsia-instancia.spool.log`):**
    * *Son la base de datos:* `16` datafiles (`3984 MB`), `2` control files (`36 MB`) y `3` online redo logs (`600 MB`).
    * *Relacionados:* `SPFILE` (`spfileFREE.ora`), `3` tempfiles (`60 MB`), `4` archived redo logs (`362 MB`) y el **password file** (`orapwFREE`), que va en *relacionados* porque almacena credenciales de usuarios `SYSDBA`/`SYSOPER` para autenticar conexiones externas antes de que la base de datos esté montada o abierta.
22. **Tamaño de `academia01.dbf` (104 865 792 bytes vs. 100 MB):** `100 MB` son `100 × 1024 × 1024 = 104 857 600` bytes de datos útiles, más `8192` bytes (1 bloque adicional) reservados para la cabecera del datafile (`OS header block`), sumando exactamente `104 865 792` bytes.
23. **Puntos únicos de fallo (SPOF):** En `11-archivos.spool.log`, los `2` control files están en el mismo directorio/volumen (`/opt/oracle/oradata/FREE/`) sin multiplexar en discos distintos, y cada grupo de Online Redo Log tiene un único miembro (`1` miembro por grupo en lugar de 2 multiplexados).
24. **ADR fuera del volumen:** Si `DIAGNOSTIC_DEST` (`/opt/oracle/diag`) queda en la capa efímera del contenedor en lugar del volumen persistente, al recrear el contenedor se pierden el `alert.log` histórico, las trazas de incidentes y los volcados de diagnóstico necesarios para auditar fallos previos.

### 8.1.6. Bloque y fila (Parte K)
25. **Descomposición del `ROWID` de la fila 101 (`12-bloque.script.log`):** Con `DBMS_ROWID` se extraen los 4 componentes: número de objeto de datos (`ROWID_OBJECT`), número de archivo relativo (`ROWID_RELATIVE_FNO`), número de bloque dentro del datafile (`ROWID_BLOCK_NUMBER`) y número de ranura/fila dentro del bloque (`ROWID_ROW_NUMBER`).
26. **Cabecera del volcado (`12-volcado-bloque.trc.txt`):** `nrow` es el número de filas almacenadas en el bloque; `fsbo` (*Free Space Begin Offset*) es el desplazamiento donde termina el directorio de filas; `fseo` (*Free Space End Offset*) es donde empieza la zona de datos de filas desde el final del bloque; `avsp` (*Available Space*) es el espacio libre contiguo entre ambos (`avsp = fseo - fsbo`).
27. **ITL con `Lck = 90`, `Flag = --U-` y *delayed block cleanout*:** Indica una transacción ya confirmada (`--U-`, *Upper bound commit*) que modificó 90 filas en ese bloque pero cuyo estado en la cabecera del bloque no se limpió en el momento del `COMMIT` para ahorrar E/S; la siguiente lectura limpia los bits de bloqueo (*delayed block cleanout*).
28. **Cálculo de los 78 bytes de la fila 101 (`12-bloque.script.log`):** Se suman los `3` bytes de cabecera de fila (`flag`, `lock`, `column count`), `1` byte de longitud por cada columna estándar (`< 250` bytes) o `3` bytes para columnas mayores, más la suma exacta de bytes de datos (`VSIZE`) de todas sus columnas.

### 8.1.7. Capacidad y coste (Parte L)
29. **Cálculo de `bfr` y `b` para `ACA_ESTUDIANTES` (`13-capacidad.log`):**
    * Con la fórmula simplificada: `bfr = floor((8192 - 96) × 0,90 / 76) = 95` filas/bloque → `b = ceil(20000 / 95) = 211` bloques.
    * Con la fórmula exacta de Oracle (cabecera de ~122 B + 2 B por entrada de directorio): `bfr = floor((8192 - 122) × 0,90 / (76 + 2)) = 93` filas/bloque → `b = ceil(20000 / 93) = 216` bloques.
    * La tabla real tiene `244` bloques bajo la HWM porque ASSM reserva bloques de mapa de bits (L1/L2/L3 BMB) y las inserciones dejan un promedio real de `86,6` filas/bloque (`231` bloques con datos).
30. **Costes medidos en `13-capacidad.log` (secciones 5a, 5b, 5c):**
    * Lectura lógica: `400 000` lecturas en `1060 ms` de CPU → **`2,65 µs`** por lectura lógica.
    * Lectura física aleatoria (1 bloque): `5464` lecturas en `288,5 ms` → **`52,8 µs`** (`lat`).
    * Lectura secuencial (multibloque): `4595` bloques en `37 ms` (~87 bloques/petición) → ancho de banda **`967 MB/s`** (`~8,05 µs/bloque`).
31. **Recálculo del umbral en un HDD (`Bw = 150 MB/s`, `lat = 5 ms`):**
    * Tiempo secuencial de `4595` bloques (`36,76 MB`): `T_sec = 36,76 MB / 150 MB/s = 245 ms` (`0,0533 ms/bloque`).
    * Coste relativo: `c_sec / c_aleat = 0,0533 ms / 5 ms = 0,0107`.
    * Umbral de rentabilidad: `k / r < (1 / 86,6) × 0,0107 = 0,000123` (**`0,012 %`** de las filas; por encima de ~50 filas de 400 000, el `FULL TABLE SCAN` en HDD ya gana al acceso por índice).
32. **Lecturas físicas en microsegundos en el contenedor:** Porque `ALTER SYSTEM FLUSH BUFFER_CACHE` vacía la caché de Oracle, pero el kernel Linux del host sigue sirviendo los bloques desde su propia *page cache* en RAM sin tocar disco físico. El método sigue siendo válido porque permite medir el coste relativo de CPU/llamadas al sistema entre acceso aleatorio de 1 bloque y lectura multibloque.

### 8.1.8. Filas migradas y encadenadas (Parte M)
33. **Migración vs. Encadenamiento (`14-filas-migradas.log`):**
    * *Migración (`row migration`):* Una fila que cabía originalmente en su bloque crece tras un `UPDATE` y no cabe en el hueco libre (`PCTFREE 0`); Oracle mueve la fila entera a otro bloque dejando en el original una cabecera (`fb: --H-----`) con el puntero `nrid`. Se cura reorganizando la tabla (`ALTER TABLE ... MOVE`).
    * *Encadenamiento (`row chaining`):* Una fila es más grande que un bloque entero (ej. `ANCHA` con ~12 000 bytes en bloque de 8 KB) y se parte en varios bloques desde su inserción. Se detectan con `ANALYZE TABLE ... LIST CHAINED ROWS` (`CHAIN_CNT`), y el encadenamiento no se cura con `MOVE` (requiere un tablespace con tamaño de bloque mayor, como 16K/32K, o rediseñar columnas).
34. **Explicación de las `3,2` lecturas lógicas por búsqueda (`14-filas-migradas.log`, sección 4):** Una búsqueda normal por clave primaria (`PK_MIGRA`) cuesta `3` lecturas lógicas (2 niveles de índice B-tree + 1 bloque de tabla). Como el `20 %` de las filas están migradas (`200` de `1000` búsquedas), ese 20 % requiere `1` lectura lógica extra para seguir el puntero `nrid` (`table fetch continued row = 200`), dando `3 + 0,20 = 3,2` lecturas lógicas de media (`3200 / 1000`).
35. **`ALTER TABLE ... MOVE` e índices `UNUSABLE` (`14-filas-migradas.log`, sección 7):** Al mover las filas a bloques nuevos cambian todos sus `ROWID`, por lo que las entradas de `PK_MIGRA` quedan apuntando a direcciones antiguas (`STATUS = UNUSABLE`). En producción se usa `ALTER TABLE ... MOVE ONLINE UPDATE INDEXES` para no bloquear el DML y mantener los índices válidos durante la operación.

### 8.1.9. Autopsia y trabajo profesional (Partes N, O)
36. **Tres hallazgos de la autopsia (`15-autopsia-instancia.spool.log` y `lab4-autopsia.md`):**
    * *Hallazgo 1 — Esquemas sin estadísticas actualizadas (`ALTURA_MAX` vacía en 4 de 5 esquemas `ADMIN_*`):* **Riesgo:** Medio (el optimizador elige planes subóptimos por falta de métricas). **Acción:** Ejecutar `DBMS_STATS.GATHER_SCHEMA_STATS` tras cargas masivas. **Prioridad:** Media.
    * *Hallazgo 2 — Errores `ORA-00800` (6 ocurrencias en `alert.log`):* **Riesgo:** Bajo (aviso por falta de `CAP_SYS_NICE` en Docker para elevar prioridad de `VKTM`). **Acción:** Documentar como esperado en entorno contenedorizado sin privilegios de tiempo real. **Prioridad:** Baja.
    * *Hallazgo 3 — Control files y redo logs sin multiplexar en volúmenes separados:* **Riesgo:** Alto en producción (punto único de fallo). **Acción:** Multiplexar miembros en almacenamiento independiente fuera de laboratorio. **Prioridad:** Alta en entornos productivos.
37. **Por qué `C##OPS_RO` y no `SYSTEM`:** Por principio de mínimo privilegio: `C##OPS_RO` solo tiene permisos de lectura del diccionario y vistas `V$`, sin ningún privilegio DML/DDL (`ops_ro_dml = 0`), evitando modificaciones accidentales durante tareas de monitorización.
38. **Dos vías de exposición de contraseñas corregidas:** (1) Eliminar contraseñas hardcodeadas de las cuentas de esquema pasando `ADMIN_*` a `NO AUTHENTICATION` (`V003`) y conectando mediante autenticación de sistema operativo (`/ as sysdba`) en los scripts de despliegue; (2) No pasar contraseñas en línea de comandos (`sqlplus sys/$ORACLE_PWD`) donde quedan visibles en `ps aux` / `/proc`, ni versionar `config/.env`.

---

## 9. Preguntas tipo examen adicionales (1Z0-182)

* **P25 — B (`PDB$SEED`):** Es la plantilla de solo lectura (`OPEN_MODE = READ ONLY`, 810 MB en `15-autopsia-instancia.spool.log`) a partir de la cual se clonan nuevas PDBs.
* **P26 — C (`ORA-65094: invalid local user or role name`):** Conectado a una PDB (`FREEPDB1`), `CREATE USER` crea un usuario local, y Oracle prohíbe que un usuario local empiece por el prefijo reservado `COMMON_USER_PREFIX` (`C##`, comprobado en `10-ciclo-vida-pdb.spool.log`).
* **P27 — B (`ALTER PLUGGABLE DATABASE p CLOSE IMMEDIATE; DROP PLUGGABLE DATABASE p INCLUDING DATAFILES;`):** Una PDB debe cerrarse antes de poder eliminarse junto con sus datafiles (`10-ciclo-vida-pdb.spool.log`).
* **P28 — A (`V$DATAFILE`) y C (`V$LOG`):** Ambas vistas dinámicas de rendimiento leen su información directamente del `control file`, que ya está cargado en estado `MOUNT` (`06-arranque-por-etapas.log`).
* **P29 — A (Que los datos salen del control file):** En la nomenclatura interna de tablas fijas `X$`, el prefijo `KCC` (*Kernel Cache Controlfile*) indica estructuras leídas del archivo de control.
* **P30 — B (En `CDB$ROOT` y en cada PDB; desde una PDB solo devuelven sus propias filas):** Las vistas `CDB_*` existen en todos los contenedores, pero muestran datos globales de toda la CDB únicamente cuando se consultan desde `CDB$ROOT` (`10-diccionario.spool.log`).
* **P31 — B (No se respaldan: se recrean si se pierden):** Los `tempfiles` almacenan ordenaciones temporales y hash joins, no generan redo ni se incluyen en backups de RMAN (`11-archivos.spool.log`).
* **P32 — B (La instancia sigue funcionando; puede recrearlo con `CREATE SPFILE FROM MEMORY;`):** Al arrancar, Oracle lee el `SPFILE` en memoria y mantiene los valores activos, permitiendo regenerar el archivo binario en disco en caliente (`07-parametros-lectura.spool.log`).
* **P33 — B (`V$PWFILE_USERS`):** Lista las cuentas almacenadas en el archivo externo de contraseñas y sus roles administrativos (`SYSDBA`, `SYSOPER`, `SYSBACKUP`, etc.).
* **P34 — A (La lista de transacciones interesadas — ITL) y B (El directorio de filas — row directory):** Ambos forman parte de la cabecera del bloque de datos antes del espacio libre (`12-volcado-bloque.trc.txt`).
* **P35 — B (Extensiones de 64 KB —8 bloques— y, al crecer, de 1 MB):** El algoritmo `AUTOALLOCATE` en tablespaces gestionados localmente comienza asignando 16 extensiones de 64 KB (1 MB total) antes de pasar a extensiones de 1 MB.
* **P36 — B (Que el espacio libre de los bloques se gestiona con mapas de bits — ASSM):** *Automatic Segment Space Management* sustituye las antiguas *freelists* por bloques de mapas de bits dentro del segmento.
* **P37 — B (`BIGFILE` gestionado localmente):** Desde Oracle Database 23ai, el tipo de tablespace por defecto al omitir la cláusula `SMALLFILE`/`BIGFILE` es `BIGFILE` con gestión local (`11-archivos.spool.log`).
* **P38 — A (Todos los bloques estaban en la buffer cache):** Tener `0` lecturas físicas significa que los 4 bloques solicitados se resolvieron directamente en memoria mediante *cache hits* (`08-memoria.spool.log`).
* **P39 — A (Aumentar `PCTFREE`) y B (Aumentar el tamaño medio de fila):** Reservar más espacio libre por bloque o tener filas más largas reduce el número de filas que caben en cada bloque (`bfr`), mientras que aumentar el tamaño de bloque lo incrementa (`13-capacidad.log`).
* **P40 — B (Todas las sesiones pasan a leer de disco hasta recalentar la caché: picos de latencia):** `FLUSH BUFFER_CACHE` vacía toda la caché compartida de la instancia global, degradando el rendimiento de todos los usuarios conectados (`08-memoria.spool.log`).
* **P41 — B (La migrada cabía en un bloque y se mudó al crecer; la encadenada no cabe en ningún bloque):** La migración ocurre por un `UPDATE` sin espacio libre suficiente en el bloque original, mientras que el encadenamiento ocurre cuando el tamaño de la fila supera el `DB_BLOCK_SIZE` (`14-filas-migradas.log`).
* **P42 — A (`ALTER INDEX ... REBUILD` — o haber usado `MOVE ONLINE`):** Reconstruye el índice leyendo los nuevos `ROWID` de la tabla tras el movimiento físico (`14-filas-migradas.log`).
* **P43 — A (`V$DIAG_ALERT_EXT`):** Expone en formato tabular SQL el contenido XML del `alert.log` dentro de la estructura ADR (`11-archivos.spool.log` y `15-autopsia-instancia.spool.log`).
* **P44 — A (Añadir un datafile o ampliar `MAXSIZE`) y B (Revisar qué segmentos crecen y por qué):** Permiten evitar el error `ORA-01653` por falta de espacio diagnosticando primero la causa del crecimiento y ampliando la capacidad del tablespace.
* **P45 — A (La SGA y los procesos de background) y B (El conjunto de online redo logs):** En la arquitectura multitenant, la instancia (memoria y procesos) y el flujo de redo/undo de instancia son únicos y compartidos por todas las PDBs (`15-autopsia-instancia.spool.log`).
* **P46 — B (`ORA-01031: insufficient privileges`):** Para cambiar de contenedor mediante `ALTER SESSION SET CONTAINER` se requiere el privilegio de sistema `SET CONTAINER`, del que carece un usuario con solo `CREATE SESSION` (`10-que-ve-cada-usuario`).
