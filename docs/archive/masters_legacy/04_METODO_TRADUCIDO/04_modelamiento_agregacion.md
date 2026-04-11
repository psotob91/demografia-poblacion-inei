6. Modelamiento de edades avanzadas (80–110)
6.1 Justificación epidemiológica y operativa

Las edades avanzadas representan un componente crítico en estudios de carga de enfermedad, dado que concentran una proporción sustantiva de eventos, especialmente mortalidad y discapacidad. Sin embargo, las fuentes demográficas suelen presentar limitaciones en este rango etario, incluyendo:

agregación en grupos abiertos (por ejemplo, “85 años y más”);
menor precisión en la distribución interna de edades;
posibles irregularidades en la forma de la curva poblacional.

Para garantizar una representación completa y utilizable de la población hasta edades avanzadas, el método incorpora un procedimiento de modelamiento que permite extender la distribución etaria hasta 110 años. Este procedimiento tiene un carácter pragmático y está orientado a producir una curva suave, monotónica y consistente con los datos observados en edades inmediatamente anteriores.

Debe hacerse explícito que el objetivo no es reconstruir la dinámica demográfica subyacente (por ejemplo, mediante tablas de vida), sino generar una extensión operativamente coherente de la distribución poblacional para fines analíticos.

6.2 Datos usados para el ajuste

El ajuste del modelo se basa en la información observada en edades cercanas al inicio de la cola etaria, específicamente en el rango de 70 a 79 años. Este rango se considera suficientemente informativo para capturar la tendencia decreciente de la población en edades avanzadas, manteniendo al mismo tiempo una base empírica relativamente estable.

El uso de este subconjunto implica el siguiente supuesto clave: la forma de la distribución poblacional en edades 70–79 contiene información relevante sobre la tendencia que se mantiene en edades superiores. Este supuesto no se deriva de una teoría demográfica formal, sino de una aproximación empírica orientada a la suavización y extrapolación.

Debe hacerse explícito que la elección de este rango es una decisión metodológica pragmática y que no está sustentada en una validación formal frente a modelos demográficos clásicos.

6.3 Especificación del modelo

El modelo utilizado se define sobre la escala logarítmica de la población, con el fin de capturar la disminución aproximadamente exponencial de la población en edades avanzadas. Formalmente, para cada combinación de sexo, ubicación y año, se ajusta un modelo de la forma:

log
⁡
(
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
)
=
𝑓
(
𝑎
)
log(P
a,s,l,t
	​

)=f(a)

donde 
𝑓
(
𝑎
)
f(a) es una función suave de la edad 
𝑎
a, aproximada mediante splines naturales con un número fijo de grados de libertad.

Una vez ajustado el modelo en el rango de edades 70–79, se generan predicciones para edades superiores, extendiendo la distribución hasta los 110 años. Para las edades donde se dispone de datos observados confiables, se mantienen dichos valores; para las edades superiores, se utilizan las predicciones del modelo.

Este enfoque combina información empírica con una función de suavización, produciendo una transición continua entre datos observados y estimados.

6.4 Supuestos del modelo

El procedimiento de modelamiento se basa en varios supuestos explícitos e implícitos:

Suavidad de la relación edad–log(población): se asume que la función 
𝑓
(
𝑎
)
f(a) es continua y suave en el rango considerado.
Monotonicidad en edades avanzadas: se impone que la población no aumenta con la edad a partir de un punto determinado (en este caso, desde los 70 años en adelante), reflejando la expectativa demográfica de disminución poblacional en edades avanzadas.
Extrapolabilidad de la tendencia 70–79: se asume que la forma observada en este rango es representativa de la tendencia en edades superiores.
Independencia por estrato: el modelo se ajusta de manera independiente para cada combinación de sexo, ubicación y año, sin compartir información entre estratos.

Estos supuestos son necesarios para la operatividad del método, pero deben ser interpretados como aproximaciones y no como representaciones exactas de la dinámica demográfica.

6.5 Propiedades prácticas del estimador

El estimador resultante presenta las siguientes propiedades prácticas:

Continuidad: la transición entre edades observadas y estimadas es suave, evitando discontinuidades abruptas.
Monotonicidad en la cola: la población decrece de manera no creciente en edades avanzadas, lo que evita patrones implausibles (por ejemplo, incrementos espurios).
Consistencia interna: la extensión de la cola etaria es coherente con la forma general de la distribución observada en edades previas.
Estabilidad numérica: el uso de la escala logarítmica reduce la influencia de variaciones extremas en los conteos.

Estas propiedades son particularmente relevantes para el uso downstream en modelos epidemiológicos, donde irregularidades en la distribución etaria pueden generar inestabilidad en estimaciones de tasas o indicadores derivados.

6.6 Limitaciones

El enfoque adoptado presenta limitaciones importantes que deben ser reconocidas explícitamente:

Ausencia de fundamentos demográficos formales: el modelo no incorpora tablas de vida, tasas de mortalidad específicas ni otros elementos de la demografía clásica.
Dependencia del rango de ajuste: la elección del rango 70–79 condiciona la forma de la extrapolación y podría no ser óptima en todos los contextos.
Falta de incertidumbre explícita: el método produce estimaciones puntuales sin cuantificación de la variabilidad asociada.
Posible sobre-suavización: el uso de funciones suaves puede ocultar irregularidades reales presentes en los datos.
Independencia entre estratos: al no compartir información entre ubicaciones o años, el modelo no aprovecha posibles patrones comunes.

Estas limitaciones han sido identificadas como áreas de mejora metodológica, incluyendo la posible incorporación futura de modelos demográficos más robustos basados en tablas de vida o enfoques como Kannisto o Coale-Kisker.

7. Construcción de agregados poblacionales
7.1 Definición de población nacional oficial

La población nacional oficial se define como el total poblacional del país reportado directamente por la fuente demográfica. Esta medida refleja la estimación institucional del tamaño poblacional nacional para cada año, edad y sexo, y se mantiene en el dataset como referencia primaria.

Metodológicamente, esta definición tiene la ventaja de preservar la fidelidad a la fuente original y garantizar coherencia con otras estadísticas oficiales que utilizan la misma base poblacional.

Sin embargo, la población nacional oficial no necesariamente coincide con la suma exacta de las poblaciones subnacionales, debido a posibles ajustes internos realizados por la institución productora de datos.

7.2 Enfoque basado en suma departamental

Con el fin de garantizar consistencia jerárquica, el método incorpora una segunda definición de población nacional, denominada población nacional aditiva. Esta se obtiene como la suma exacta de las poblaciones departamentales para cada combinación de edad, sexo y año:

𝑃
𝑎
,
𝑠
,
𝑡
(
𝑛
𝑎
𝑡
_
𝑎
𝑑
𝑑
)
=
∑
𝑙
∈
𝐿
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
P
a,s,t
(nat_add)
	​

=
l∈L
∑
	​

P
a,s,l,t
	​


donde 
𝐿
L representa el conjunto de departamentos.

Esta definición asegura que cualquier agregación desde el nivel subnacional reproduzca exactamente el total nacional, lo cual es particularmente importante en análisis que integran múltiples niveles geográficos o que requieren consistencia aritmética estricta.

7.3 Comparación con estimaciones oficiales

La coexistencia de la población nacional oficial y la población nacional aditiva implica que pueden existir discrepancias entre ambas. Estas diferencias reflejan:

ajustes demográficos realizados por la fuente oficial;
redondeos o reconciliaciones internas;
posibles diferencias en la forma de agregación.

El método no intenta reconciliar estas diferencias mediante ajustes adicionales, sino que las reconoce explícitamente y mantiene ambas definiciones como parte del dataset analítico.

Desde una perspectiva metodológica, esta decisión evita introducir supuestos adicionales no verificables y preserva la transparencia del proceso.

7.4 Implicancias analíticas

La existencia de dos definiciones de población nacional tiene implicancias importantes para el análisis:

Elección del denominador:
la población nacional oficial es adecuada cuando se busca alineamiento con estadísticas institucionales;
la población nacional aditiva es preferible cuando se requiere consistencia exacta con análisis subnacionales.
Interpretación de tasas:
las tasas calculadas con cada definición pueden diferir ligeramente, especialmente cuando las discrepancias entre ambas poblaciones son relevantes.
Consistencia jerárquica:
el uso de la población aditiva garantiza que los totales nacionales sean exactamente iguales a la suma de sus componentes, lo cual es crítico en modelos jerárquicos o en validaciones internas.

Debe hacerse explícito que la elección entre ambas definiciones no es meramente técnica, sino que depende del objetivo analítico. Esta decisión constituye una de las principales convenciones metodológicas del componente y debe ser comunicada claramente a los usuarios del dataset.