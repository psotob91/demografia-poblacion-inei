# Registro de Hallazgos, Limitaciones y Mejoras Futuras

Este documento registra de manera estructurada:

1. Problemas detectados en el código actual
2. Limitaciones metodológicas
3. Decisiones subóptimas pero pragmáticas
4. Propuestas de mejora futura (no implementadas aún)

IMPORTANTE:
- No todo debe corregirse ahora
- Este documento guía la evolución del pipeline
- Debe mantenerse alineado con los métodos documentados

---

## 1. Hallazgos del código actual

### [H-001] Inferencia de sexo desde nombre de hoja

Tipo: Técnica / Parsing
Fuente: scripts/02_normaliza_long_omop.R

Descripción:
El sexo se infiere desde el nombre de la hoja Excel utilizando heurísticas de texto.

Riesgo:
- Dependencia fuerte del naming
- Posibles errores silenciosos

Impacto:
Medio

Propuesta:
- Crear maestro explícito de mapping sheet → sex
- O incorporar validación contra estructura INEI oficial

---

## 2. Limitaciones metodológicas

### [M-001] Extrapolación spline 70–79 → 80–110

Tipo: Estadística

Descripción:
Se usa modelo:
log(pop) ~ ns(age, df=4)

Limitaciones:
- No incorpora mortalidad real
- No usa life tables
- No garantiza coherencia demográfica completa

Propuesta futura:
- Integrar life tables (tabla de vida estándar)
- Usar modelo Kannisto / Coale-Kisker

Prioridad:
Alta (para siguiente versión)

### [M-002] Falta de justificación explícita del rango de ajuste 70–79

Tipo: metodológica.

El código implementa el rango, pero no documenta por qué ese tramo fue elegido.

### [M-003] Falta de explicitación del sentido epidemiológico de la monotonicidad 70+
Tipo: metodológica.

La restricción existe, pero no se argumenta su racionalidad ni sus implicancias.

### [M-004] La coherencia evaluada es estructural/arimética, no demográfica integral

Tipo: metodológica.

Conviene evitar sobreinterpretación del QC.

---

## 3. Decisiones de diseño

### [D-001] Nacional aditivo (9000)

Descripción:
Se construye nacional alternativo como suma de departamentos.

Ventaja:
Consistencia jerárquica

Limitación:
Difiere del nacional oficial INEI (00)

Recomendación:
- Mantener ambos explícitamente documentados
- Evaluar cuál usar en downstream (GBD vs policy)

### [D-002] Coexistencia de dos definiciones nacionales requiere guía de uso analítico

Tipo: estructural/metodológica.

Debe aclararse cuándo usar 0 y cuándo 9000.

---

## 4. Problemas estructurales del repositorio

### [S-001] Mezcla de responsabilidades en scripts

Descripción:
Algunos scripts hacen múltiples tareas (transformación + validación + export)

Propuesta:
- Separar en:
  - transform
  - validate
  - export

---

### [S-002] Falta de data model explícito

Descripción:
No existe documento formal del modelo de datos

Propuesta:
- Crear DATA_MODEL.md (fase Codex)

### [S-003] Falta una sección formal de supuestos del método en la documentación

Tipo: estructural.

Los supuestos existen de facto, pero no están consolidados.

---

## 5. Diccionarios y maestros faltantes

### [DICT-001] Falta diccionario para staging raw_long

Propuesta:
- Crear diccionario formal para raw_long.parquet

---

### [DICT-002] Falta maestro de edades

Propuesta:
- Tabla estándar de grupos de edad
- Compatible con GBD

---

## 6. Roadmap sugerido

### Corto plazo (documentación)
- Completar MD metodológico
- Documentar QC completamente

### Mediano plazo (estructura)
- Refactor de scripts
- Nuevos maestros

### Largo plazo (metodología)
- Integración con life tables
- Armonización GBD/WHO
