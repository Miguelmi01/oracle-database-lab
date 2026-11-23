# Bitácora Lab 5 — Oracle DBA Workflow II

## Bloque 1: Índices medidos con números

1. **Anatomía del índice (`PK_PEDIDO` vs `IX_PED_CLIENTE`)**:
   - `PK_PEDIDO` tiene **1.875 hojas** al **99,9 %** de ocupación viva (media de 533 entradas/hoja) porque las claves `PEDIDO_ID` entraron en orden estrictamente creciente durante la carga masiva, provocando divisiones 90/10 sin dejar hueco libre.
   - `IX_PED_CLIENTE` tiene **2.216 hojas** al **89,7 %** de ocupación (451 entradas/hoja) porque se construyó con `CREATE INDEX` tras la carga, respetando el `PCTFREE 10` por defecto.
2. **Factor de agrupamiento (*Clustering Factor*) y punto de equilibrio**:
   - Un índice sobre columnas ordenadas físicamente respecto a la tabla (`CLUSTERING_FACTOR` cercano al número de bloques de la tabla) lee muy pocos bloques de tabla al recorrer un rango. Si el *clustering factor* se acerca al número de filas, cada entrada del índice salta a un bloque distinto de la tabla, disparando las lecturas lógicas y haciendo que el optimizador prefiera un `TABLE ACCESS FULL` en cuanto la selectividad supera un porcentaje bajo (punto de equilibrio).
3. **Reglas de sargabilidad**:
   - Aplicar funciones sobre la columna indexada (`TRUNC(fecha)`, `UPPER(email)`), operar aritméticamente sobre ella (`importe * 1.21 > 100`) o usar comodines iniciales (`LIKE '%texto'`) impide hacer un `INDEX RANGE SCAN` estándar, degradando el plan a `INDEX FAST FULL SCAN` o `TABLE ACCESS FULL`. Reescribir con rangos cerrados (`fecha >= ... AND fecha < ...`) o índices basados en función devuelve el acceso directo por índice.
4. **Protocolo de diseño y coste de escritura (`V005`)**:
   - Con los 5 índices definitivos sobre `PEDIDO` (`PK_PEDIDO`, `IX_PED_CLI_FEC_CUB`, `IX_PED_CP`, `IX_PED_FECHA`, `IX_PED_PENDIENTES`), cada `INSERT` modifica **12,1 bloques** (1.610 bytes de redo) y un `UPDATE` sobre columna indexada (`estado`) modifica **8,1 bloques** (1.034 bytes de redo) frente a **6 bloques** (812 bytes de redo) cuando se actualiza una columna no indexada (`importe`). Solo se indexan columnas que justifican su coste de escritura en lecturas críticas.
5. **Divisiones de hoja y patrón cola**:
   - Las inserciones aleatorias provocan divisiones **50/50** (dejando hojas al ~50 % de ocupación). En el patrón cola (inserción por la derecha con clave creciente y borrado antiguo por la izquierda), el mapa de ocupación muestra hojas vacías o casi vacías a la izquierda y llenas (`#`) a la derecha; se remedia con `ALTER INDEX ... COALESCE` (compacta hojas adyacentes online sin bloquear DML) o `REBUILD ONLINE`.

---

## Bloque 2: Durabilidad, WAL y Simulacros (Game Day)

6. **SCN, Checkpoints y Write-Ahead Logging (WAL)**:
   - El SCN es el reloj lógico monotónico de Oracle. En un `COMMIT`, **LGWR** escribe inmediatamente el registro de redo en disco antes de confirmar al cliente (WAL), mientras **DBWn** difiere la escritura de bloques sucios hasta un *checkpoint* o presión en caché. Asimismo, toda modificación de *undo* genera su propio *redo* para proteger la consistencia transaccional ante caídas.
7. **Alta disponibilidad física (`CONTROL_FILES`, Redo Logs y `ARCHIVELOG` + FRA)**:
   - Se multiplexaron los *control files* en 3 copias (`control01.ctl`, `control02.ctl`, `control03.ctl`) y los grupos de *online redo log* a 2 miembros cada uno. Se activó `ARCHIVELOG` con una Fast Recovery Area (FRA) de 4 GB para conservar el historial de cambios y permitir recuperación a un punto en el tiempo o de medios sin pérdida de datos.
8. **Resultados de los simulacros de fallo (Game Day A–D)**:

| Simulacro | Escenario de fallo | Mecanismo de recuperación | RTO medido | RPO medido |
| :--- | :--- | :--- | :--- | :--- |
| **A** | Caída brusca de instancia (`SHUTDOWN ABORT`) | Recuperación automática de instancia por **SMON** (roll-forward de 20 KB redo / 28 bloques + rollback de fila 103 no confirmada) | Automático (~segundos) | **0** (confirmados) |
| **B** | Pérdida de 1 control file (`control03.ctl`) | Copia en estado `NOMOUNT` desde `control01.ctl` + `MOUNT` + `OPEN` | Segundos (manual) | **0** |
| **C** | Borrado de tabla con `PURGE` (`ACA_MATRICULAS`) | Restauración completa desde backup en frío (`lab5-pre-simulacro`) | **321 s** | **2 s** (ventana desde backup) |
| **D** | Pérdida física de datafile (`academia01.dbf`) | `RESTORE DATAFILE` + `RECOVER DATAFILE` online en **RMAN** + `ARCHIVELOG` | **12 s** (11 s offline->online) | **0** (fila 104 sobrevivió) |

9. **Conclusión operativa (Simulacro C vs D)**:
   - Sin `ARCHIVELOG` (Simulacro C), recuperar un borrado lógico obliga a restaurar toda la base de datos perdiendo las transacciones posteriores a la copia (RTO = 321 s, RPO > 0). Con `ARCHIVELOG` y RMAN (Simulacro D), el fallo físico de un datafile se aísla y repara aplicando los *archived redo logs* con **RPO = 0** y un **RTO de 12 s**.
