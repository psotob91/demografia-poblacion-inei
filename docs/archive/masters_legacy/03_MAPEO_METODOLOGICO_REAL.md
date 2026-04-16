Mapeo metodológico sección por sección

A continuación, para cada sección indico:

Implementado: lo que sí está respaldado por el código.
No explícito en el código: lo que el documento debería explicar pero no aparece formalizado como método.
Debe hacerse explícito: decisiones metodológicas implícitas que conviene declarar.

0. Propósito y alcance

Implementado
El repositorio sí deja claro que busca construir un dataset canónico de población por edad, sexo, ubicación y año, con una salida adicional jerárquica y con trazabilidad para uso downstream en mortalidad, AVP, morbilidad y carga de enfermedad.

No explícito en el código
El código no formula de manera narrativa el rol epidemiológico del componente demográfico dentro de un estudio de carga de enfermedad.

Debe hacerse explícito
Que este componente produce denominadores poblacionales analíticos y no estimaciones demográficas originales del tipo censo-proyección propia.

1. Marco conceptual

Implementado
La unidad analítica final sí está materializada como combinaciones de year_id, age, sex_id y location_id, con una llave primaria lógica explícita en la spec.

No explícito en el código
No hay una sección conceptual que explique por qué esa unidad analítica es la adecuada para estimación de tasas, AVP y AVISA.

Debe hacerse explícito
Que la población aquí funciona como denominador compatible con desagregación por edad simple, sexo binario final y ubicación departamental/nacional.

2. Fuentes de datos

Implementado
El código descarga y procesa archivos públicos del INEI por ubicación, usando una base URL fija y maestros de ubicación/sexo. El árbol del proyecto muestra cobertura de archivos cap00.xlsx a cap25.xlsx.

No explícito en el código
No hay una evaluación formal de calidad de fuente en sentido epidemiológico; solo hay validación operativa de existencia, parseabilidad y estructura.

Debe hacerse explícito
Que la “evaluación de calidad” implementada es principalmente estructural y operativa, no una auditoría demográfica externa contra fuentes independientes.

3. Definiciones operativas

Implementado
La spec define formalmente edad, año, población, sexo permitido y ubicación permitida. La edad final es simple 0–110, el año es calendario, el sexo final permitido es 8507/8532, y la ubicación incluye 00–25 en el dataset canónico.

No explícito en el código
No está redactado como definiciones metodológicas legibles para un lector no técnico.

Debe hacerse explícito
Tres convenciones locales cruciales:

en staging existe sexo total como convención local 0;
en el output final solo quedan masculino y femenino;
el nacional oficial es 0 y el nacional aditivo es 9000.
4. Construcción del dataset analítico

Implementado
Sí existe un proceso real de:

ingesta y parsing de hojas Excel,
estandarización de columnas,
inferencia/armonización de sexo,
clasificación de edad,
generación del dataset base para luego producir el analítico final.

No explícito en el código
El código no expone en lenguaje metodológico qué se considera “inconsistencia estructural” ni cómo se justifica epidemiológicamente cada regla de armonización.

Debe hacerse explícito
Que este paso no corrige errores demográficos sustantivos del INEI; más bien los transforma a un contrato analítico consistente.

5. Tratamiento de edad

Implementado
El código distingue total, edad simple y grupo de edad; extrae edades simples cuando están disponibles; y trata grupos abiertos como “85 y más” asignando extremo superior 110 en staging.

No explícito en el código
No hay una justificación metodológica formal del uso de edad simple ni del uso de 110 como techo operativo.

Debe hacerse explícito
Que el objetivo es producir una malla analítica completa 0–110 para compatibilidad downstream, y que el grupo abierto no se usa como resultado final tal cual, sino como insumo dentro del proceso.

6. Modelamiento de edades avanzadas (80–110)

Implementado
Esto sí está claramente implementado. El script ajusta, por estrato de ubicación-año-sexo, un modelo log(population) ~ ns(age, df = 4) usando edades 70–79; predice sobre 0–110; luego fusiona observado y predicho; y fuerza monotonicidad no creciente desde 70 años.

No explícito en el código
No están explicitadas:

la justificación epidemiológica de elegir 70–79,
la razón para df = 4,
la interpretación estadística del estimador,
la razón de imponer monotonicidad a partir de 70 y no solo desde 80.

Debe hacerse explícito
Que este no es un modelo demográfico completo ni usa tablas de vida, mortalidad observada o modelos de supervivencia de edades extremas; es una extrapolación pragmática suavizada. Esto ya está reconocido como limitación en el master de hallazgos.

7. Construcción de agregados poblacionales

Implementado
Sí existen dos nociones de nacional:

nacional oficial incluido en el dataset canónico (location_id = 0);
nacional aditivo construido como suma exacta de departamentos (location_id = 9000).

No explícito en el código
No está escrito metodológicamente cuándo conviene usar cada uno.

Debe hacerse explícito
Que el nacional oficial preserva la fuente institucional tal como viene, mientras que el nacional aditivo prioriza consistencia jerárquica exacta para análisis agregados y validaciones subnacionales.

8. Consistencia interna y coherencia demográfica

Implementado
Sí hay chequeos de:

unicidad de llave primaria,
no negatividad,
monotonicidad de cola,
comparación entre nacional oficial y suma departamental,
exactitud obligatoria del nacional aditivo respecto a departamentos.

No explícito en el código
No existe una evaluación de coherencia demográfica fuerte, por ejemplo razón de sexos por edad, balance cohortal, ni consistencia con tablas de vida.

Debe hacerse explícito
Que la “coherencia” implementada es sobre todo estructural y aritmética; no equivale a validación demográfica profunda.

9. Supuestos del método

Implementado
Los supuestos están dispersos en reglas operativas del código:

nombres de hojas permiten inferir sexo,
archivos siguen cierta estructura tabular con encabezados detectables por “Edad”,
edades 70–79 son aptas para ajustar la cola,
la población a edades altas debe ser no creciente desde 70+.

No explícito en el código
No hay una sección única de supuestos.

Debe hacerse explícito
Separar supuestos en tres grupos:

de entrada,
de modelamiento,
estructurales de agregación.
10. Limitaciones

Implementado
Algunas limitaciones están implícitas en el comportamiento del código y otras ya están registradas en el master de hallazgos: inferencia de sexo por nombre de hoja, extrapolación spline sin tablas de vida, etc.

No explícito en el código
No hay una discusión metodológica consolidada de limitaciones.

Debe hacerse explícito
Al menos estas:

dependencia del naming de hojas;
ausencia de validación demográfica externa;
extrapolación de cola basada en ajuste estadístico pragmático;
diferencia entre nacional oficial y aditivo.
11. Fortalezas del enfoque

Implementado
Sí hay reproducibilidad operacional, contrato de datos, QC automatizado y trazabilidad de artefactos/corridas.

No explícito en el código
No está argumentado por qué eso es una fortaleza epidemiológica.

Debe hacerse explícito
Que la fortaleza principal no es “estimar mejor que INEI”, sino producir una base analítica consistente, auditable y reusable para estudios de carga de enfermedad.

12. Uso en el pipeline de carga de enfermedad

Implementado
El README sí declara explícitamente su uso downstream en mortalidad, AVP, morbilidad y carga de enfermedad.

No explícito en el código
El repositorio no calcula tasas, AVP ni AVISA por sí mismo.

Debe hacerse explícito
Que este anexo solo documenta el componente demográfico-denominador y no el cálculo completo de los indicadores de carga.

13. Interpretación de resultados

Implementado
El output final representa conteos absolutos de población por celda analítica. Eso sí está definido en spec y diccionarios.

No explícito en el código
No se explica qué no representa.

Debe hacerse explícito
Que no representa incertidumbre poblacional, ni ajuste demográfico integral, ni equivalencia automática entre nacional oficial y suma subnacional.

14. Comparación con enfoques alternativos

Implementado
No está implementada ninguna comparación formal con GBD, OMS o métodos clásicos.

No explícito en el código
Toda esta sección será necesariamente interpretativa y comparativa.

Debe hacerse explícito
Que la comparación será conceptual, no empírica, salvo que en otro repo existan benchmarks formales.

15. Mejoras futuras identificadas

Implementado
Sí existe ya un registro maestro con mejoras: integrar life tables, refactor estructural, crear modelos de datos explícitos, mejorar diccionarios.

No explícito en el código
No hay priorización formal dentro del pipeline mismo.

Debe hacerse explícito
La clasificación por tipo: técnica, metodológica y estructural.

16. Conclusión

Implementado
No como conclusión narrativa.

No explícito en el código
Debe redactarse.

Debe hacerse explícito
Que el método real es un procedimiento de estandarización + extrapolación pragmática + validación estructural, útil para carga de enfermedad pero no equivalente a una reconstrucción demográfica integral.

Síntesis global de hallazgos
1) Partes del método implementadas correctamente

Estas sí están claras y respaldadas por código:

definición de la unidad analítica final por año, edad simple, sexo y ubicación;
ingestión y parsing de archivos INEI por ubicación;
armonización de sexo y exclusión del sexo total en el output final;
uso de edad simple como formato final;
extensión de edades avanzadas hasta 110;
especificación operativa del modelo de extrapolación;
construcción de nacional aditivo a partir de suma departamental;
construcción de una vista jerárquicamente consistente;
validación estructural y jerárquica con QC automatizado.
2) Partes no explícitas en el código

Estas deben aparecer en el anexo aunque el código no las formule narrativamente:

justificación epidemiológica del uso de edad simple;
justificación del techo etario 110;
justificación de elegir 70–79 para el ajuste;
interpretación del spline como aproximación pragmática y no demográfica clásica;
criterios para preferir nacional oficial versus nacional aditivo;
rol exacto del denominador en tasas, AVP y AVISA;
alcance de la “coherencia” evaluada por los QC.
3) Decisiones metodológicas implícitas que deben hacerse explícitas

Estas son especialmente importantes:

el staging admite sexo total, pero el dataset final no;
el nacional oficial y el nacional aditivo coexisten porque cumplen funciones distintas;
la cola etaria se fuerza a ser no creciente, lo cual es una restricción operativa fuerte;
la extrapolación no incorpora mortalidad observada ni tablas de vida;
la calidad validada es principalmente estructural, no demográfica externa;
el método prioriza utilidad analítica y consistencia downstream sobre sofisticación demográfica máxima.