4. Construcción del dataset analítico
4.1 Estandarización de estructuras de entrada

Los datos poblacionales provenientes de la fuente oficial presentan heterogeneidad en su estructura de presentación, incluyendo variaciones en la disposición de encabezados, organización de columnas y formato de las variables. Por ello, el primer paso metodológico consiste en estandarizar dichas estructuras hacia un formato analítico común.

Esta estandarización implica transformar tablas originalmente diseñadas para difusión en una representación longitudinal (“long format”), donde cada fila corresponde a una única combinación de edad, sexo, ubicación y año. Este cambio de estructura no altera el contenido sustantivo de los datos, sino que permite su integración coherente en un esquema analítico uniforme.

Desde el punto de vista epidemiológico, este paso es fundamental para garantizar que todas las observaciones sean comparables entre sí y que puedan ser utilizadas como denominadores consistentes en análisis posteriores.

4.2 Armonización de variables clave

Una vez estandarizada la estructura, se procede a la armonización de las variables principales:

Edad: se transforma a edad simple en años cumplidos, independientemente de la forma original de presentación.
Sexo: se asigna de manera consistente a las categorías masculino y femenino en el dataset final.
Ubicación geográfica: se normaliza a un conjunto fijo de unidades departamentales y nacional.
Año calendario: se extrae y estandariza como variable discreta.

Este proceso implica resolver ambigüedades presentes en la fuente, como la identificación indirecta del sexo o la coexistencia de distintas representaciones de edad. La armonización asegura que todas las observaciones cumplan con la definición operativa establecida en la sección anterior.

Debe hacerse explícito que esta etapa no corrige errores demográficos de la fuente, sino que los adapta a un esquema analítico consistente. Por tanto, cualquier sesgo o limitación inherente a los datos originales se preserva en el dataset final.

4.3 Resolución de inconsistencias estructurales

Durante la integración de los datos pueden surgir inconsistencias estructurales, tales como:

duplicación de registros para una misma combinación analítica;
valores fuera de rango en edad o año;
presencia de categorías no previstas (por ejemplo, sexo no clasificable);
celdas con valores faltantes o inconsistentes.

El método establece reglas explícitas para detectar y resolver estas inconsistencias, priorizando la coherencia interna del dataset. Entre estas reglas destacan:

la exigencia de unicidad de la unidad analítica;
la restricción de valores a rangos válidos;
la eliminación o exclusión de categorías no compatibles con la definición operativa final.

Es importante enfatizar que estas reglas buscan garantizar consistencia estructural y no implican una validación externa de la veracidad de los datos. En este sentido, la “limpieza” de datos debe interpretarse como una estandarización analítica y no como una corrección demográfica.

4.4 Generación del dataset base

Como resultado de los pasos anteriores, se obtiene un dataset base que contiene:

población por edad simple, sexo, ubicación y año;
valores enteros no negativos;
ausencia de duplicados en la unidad analítica;
cumplimiento de las definiciones operativas establecidas.

Este dataset constituye la base sobre la cual se aplican transformaciones adicionales, en particular el tratamiento de edades avanzadas y la construcción de agregados nacionales.

Desde una perspectiva metodológica, este dataset base representa la traducción de la fuente demográfica original a un “contrato analítico” consistente, que puede ser utilizado de manera directa en modelos epidemiológicos y en cálculos de carga de enfermedad.

5. Tratamiento de edad
5.1 Uso de edad simple

El método adopta la edad simple (años cumplidos) como unidad fundamental de análisis etario. Esta decisión permite una representación más granular de la estructura poblacional y facilita:

la construcción de tasas específicas por edad;
la agregación flexible hacia grupos etarios (por ejemplo, quinquenales);
la compatibilidad con diferentes estándares de estandarización poblacional.

El uso de edad simple es coherente con prácticas internacionales en estudios de carga de enfermedad, donde la precisión en la distribución etaria es crítica para estimar correctamente indicadores sensibles a la edad.

Debe hacerse explícito que, aunque las fuentes pueden proporcionar información en grupos de edad agregados, el método transforma dicha información para integrarla en una escala de edad simple, asegurando homogeneidad en todo el dataset.

5.2 Manejo de grupos abiertos

Las fuentes demográficas frecuentemente presentan grupos de edad abiertos en edades avanzadas (por ejemplo, “85 años y más”). Estos grupos no son directamente compatibles con una representación en edad simple, por lo que requieren un tratamiento específico.

El método considera estos grupos abiertos como insumos informativos sobre la población en edades avanzadas, pero no los utiliza directamente como categorías finales. En cambio, se integran dentro de un proceso posterior de modelamiento que permite distribuir la población en edades específicas más allá del límite inferior del grupo abierto.

Este enfoque evita asignaciones arbitrarias dentro del grupo abierto y permite mantener coherencia con la estructura de edad simple adoptada.

5.3 Extensión de la cola etaria

Para garantizar una cobertura completa de la distribución poblacional, el método extiende la edad hasta un máximo de 110 años. Esta extensión responde a dos objetivos:

Cierre de la distribución etaria: asegurar que toda la población esté representada dentro de un rango finito y definido.
Compatibilidad analítica: facilitar la integración con modelos y métricas que requieren una distribución completa de edades.

La extensión de la cola etaria no se basa exclusivamente en datos observados, ya que las fuentes suelen ser menos precisas en edades avanzadas. Por ello, se recurre a un procedimiento de modelamiento descrito en la siguiente sección, que permite estimar la población en edades superiores a las observadas directamente.

Debe hacerse explícito que el límite superior de 110 años es una convención operativa y no una afirmación empírica sobre la edad máxima de la población. Asimismo, la distribución en edades avanzadas debe interpretarse con cautela, dado que se apoya en supuestos adicionales y en un proceso de suavización estadística.

En conjunto, el tratamiento de la edad en este método busca equilibrar fidelidad a la fuente, coherencia interna y utilidad analítica, reconociendo las limitaciones inherentes a la información disponible en edades extremas.