# Runbook: Perdida de un Datafile de Aplicacion en una PDB (ARCHIVELOG)

## 1. Sintoma y Diagnostico
El alert log (V$DIAG_ALERT_EXT) registra la triada de errores de E/S sobre el archivo desaparecido:
- ORA-01116: error in opening database file <N>
- ORA-01110: data file <N>: '<ruta_datafile>'
- ORA-27041: unable to open file (No such file or directory)
- Si DBWn detecta antes el fallo de medios, Oracle aisla la PDB cerrandola (MOUNTED) y registra ORA-63999.

## 2. Comprobaciones Previas (en CDB$ROOT)
1. Confirmar modo ARCHIVELOG: SELECT log_mode FROM v$database;
2. Identificar archivo y estado de la PDB: SELECT file#, name, status FROM v$datafile WHERE file# = <N>; y SELECT name, open_mode FROM v$pdbs;
3. Verificar copia valida en RMAN: rman target / -> LIST BACKUP OF DATAFILE <N>;

## 3. Procedimiento de Recuperacion (RMAN + SQL*Plus)
- Caso A (PDB abierta READ WRITE): en FREEPDB1 ejecutar ALTER DATABASE DATAFILE <N> OFFLINE; en RMAN ejecutar RESTORE DATAFILE <N>; RECOVER DATAFILE <N>; y volver a poner ONLINE.
- Caso B (PDB cerrada MOUNTED tras ORA-63999): en RMAN ejecutar RESTORE DATAFILE <N>; RECOVER DATAFILE <N>; y en CDB$ROOT abrir con ALTER PLUGGABLE DATABASE FREEPDB1 OPEN;

## 4. Verificacion y Escalado
- Confirmar open_mode = READ WRITE en v$pdbs, estado ONLINE en v$datafile_header y acceso a las tablas afectadas.
- Escalar al equipo de Sistemas/Almacenamiento para revisar el disco y reportar RTO/RPO al responsable de guardia.
