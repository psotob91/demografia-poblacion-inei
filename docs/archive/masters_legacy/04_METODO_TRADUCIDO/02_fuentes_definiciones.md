2. Fuentes de datos
2.1 Datos poblacionales del INEI

El componente demográfico utiliza como fuente primaria los datos poblacionales oficiales producidos por el Instituto Nacional de Estadística e Informática (INEI) del Perú. Estos datos corresponden a estimaciones y/o proyecciones poblacionales por edad, sexo, ubicación geográfica y año calendario, publicadas en formatos tabulares estructurados.

Desde una perspectiva metodológica, el uso de una fuente oficial garantiza alineamiento con las estadísticas nacionales vigentes y facilita la comparabilidad con otros productos institucionales. No obstante, el presente componente no replica el proceso de estimación demográfica del INEI, sino que transforma dichas estimaciones en una estructura analítica homogénea para su uso en estudios de carga de enfermedad.

Debe hacerse explícito que el método asume que las cifras del INEI constituyen la mejor aproximación disponible a la población real en cada estrato, y que no se implementan ajustes demográficos adicionales (por ejemplo, correcciones por subregistro o reconciliación con fuentes alternativas).

2.2 Cobertura temporal y geográfica

La cobertura del dataset analítico se extiende a un rango de años calendario predefinido, comprendido entre 1995 y 2030, con desagregación geográfica a nivel nacional y departamental. La unidad geográfica corresponde al departamento (primer nivel administrativo), incluyendo una categoría nacional.

Esta cobertura responde a necesidades analíticas de estudios longitudinales de carga de enfermedad, donde se requiere consistencia temporal prolongada y comparabilidad entre regiones. La inclusión de todos los departamentos asegura representatividad territorial completa dentro del país.

Adicionalmente, el método incorpora dos representaciones del nivel nacional:

una representación oficial, correspondiente a la población nacional publicada por la fuente;
una representación aditiva, obtenida como la suma exacta de las poblaciones departamentales.

Ambas representaciones coexisten porque cumplen funciones analíticas distintas: la primera preserva la referencia institucional, mientras que la segunda garantiza consistencia jerárquica en análisis agregados.

2.3 Evaluación de calidad de la fuente

La evaluación de calidad implementada en este componente es de carácter principalmente estructural y operativo. Esto implica que se verifica:

la integridad de las dimensiones analíticas (edad, sexo, ubicación y año);
la ausencia de duplicados en la unidad analítica;
la validez de los rangos de edad y tiempo;
la no negatividad de los conteos poblacionales.

Asimismo, se evalúa la coherencia aritmética entre niveles geográficos, particularmente la consistencia entre el nivel nacional y la suma de unidades subnacionales.

Sin embargo, es importante enfatizar que este enfoque no constituye una validación demográfica exhaustiva. No se evalúan, por ejemplo:

patrones de mortalidad implícitos en la estructura etaria;
coherencia cohortal;
razón de sexos por edad;
concordancia con tablas de vida u otras fuentes externas.

Por tanto, la calidad de la fuente se asume válida en términos demográficos generales, y el componente se limita a asegurar su adecuación para el uso analítico previsto.

2.4 Limitaciones conocidas de los datos

El uso de datos poblacionales oficiales conlleva limitaciones inherentes que deben ser reconocidas explícitamente:

Dependencia de la estructura de publicación: los datos provienen de tablas diseñadas para difusión estadística, no necesariamente para análisis epidemiológico, lo que obliga a procesos de armonización.
Presencia de agregaciones no directamente utilizables: algunas tablas incluyen totales o grupos de edad abiertos que requieren transformación para integrarse en una malla de edad simple.
Posibles discrepancias entre niveles geográficos: la población nacional oficial puede no coincidir exactamente con la suma de poblaciones departamentales, lo que motiva la construcción de un agregado alternativo.
Ausencia de información explícita de incertidumbre: las estimaciones poblacionales no incluyen intervalos de confianza ni medidas de variabilidad, lo que limita el tratamiento formal de la incertidumbre en análisis posteriores.
Limitaciones en edades avanzadas: las edades altas suelen presentarse en forma agregada o con menor precisión, lo que requiere modelamiento adicional para extender la cola etaria.

Estas limitaciones no invalidan el uso de la fuente, pero sí condicionan el diseño metodológico del componente y justifican las transformaciones aplicadas en secciones posteriores.

3. Definiciones operativas
3.1 Definición de población

La población se define como el número de personas residentes en una unidad geográfica específica, pertenecientes a un grupo de edad y sexo determinados, en un año calendario dado. En el dataset analítico, esta definición se operacionaliza como un conteo absoluto de individuos por celda definida por edad, sexo, ubicación y año.

Formalmente, la población puede representarse como:

𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
P
a,s,l,t
	​


donde:

𝑎
a corresponde a la edad en años cumplidos,
𝑠
s al sexo,
𝑙
l a la ubicación geográfica,
𝑡
t al año calendario.

Los valores de 
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
P
a,s,l,t
	​

 son enteros no negativos y constituyen el insumo directo para el cálculo de tasas y otros indicadores epidemiológicos.

3.2 Definición de edad

La edad se define como edad simple en años cumplidos al momento de referencia, y se expresa como una variable discreta entera en el rango de 0 a 110 años.

El uso de edad simple responde a la necesidad de máxima flexibilidad analítica, permitiendo:

agregaciones posteriores en grupos quinquenales u otras categorías;
compatibilidad con diferentes esquemas de estandarización;
alineamiento con requerimientos de modelos epidemiológicos que operan a nivel de edad individual.

En los datos fuente pueden existir grupos de edad agregados (por ejemplo, “85 y más”). Estos grupos se transforman dentro del método para integrarse en la escala de edad simple, siendo posteriormente utilizados como insumo para la extensión de la cola etaria.

El valor máximo de 110 años debe entenderse como un límite operativo que permite cerrar la distribución etaria en análisis, y no como una afirmación sobre la máxima edad real observada.

3.3 Definición de sexo

El sexo se define como una variable categórica binaria con dos categorías finales:

masculino
femenino

En el proceso de construcción del dataset pueden existir registros agregados que incluyen ambos sexos (sexo total). Sin embargo, estos no forman parte del dataset analítico final, el cual se restringe a las dos categorías mencionadas.

Esta decisión metodológica responde a la necesidad de consistencia con la mayoría de fuentes epidemiológicas y de carga de enfermedad, que reportan resultados desagregados al menos por sexo masculino y femenino. La exclusión del sexo total en el resultado final evita duplicidades y ambigüedades en la interpretación de los denominadores.

Debe hacerse explícito que esta restricción es una convención del método y no necesariamente refleja todas las formas de desagregación posibles en fuentes demográficas.

3.4 Definición de ubicación geográfica

La ubicación geográfica se define a nivel de departamento, correspondiente al primer nivel administrativo del país. Cada unidad geográfica se identifica mediante un código único, incluyendo:

una categoría nacional oficial, que representa la población total del país;
categorías subnacionales correspondientes a cada departamento.

Adicionalmente, el método introduce una categoría nacional alternativa (nacional aditivo), construida como la suma exacta de las poblaciones departamentales. Esta categoría no sustituye a la nacional oficial, sino que coexiste con ella para fines analíticos específicos.

La inclusión de ambas definiciones permite:

preservar la fidelidad a la fuente oficial;
garantizar consistencia jerárquica en análisis que requieren agregación exacta.
3.5 Definición de año calendario

El año se define como año calendario completo y se representa como una variable discreta entera. Cada observación poblacional corresponde a un punto en el tiempo asociado a un año específico.

Esta definición es consistente con la mayoría de fuentes epidemiológicas y permite la alineación directa con numeradores de eventos que se reportan en la misma escala temporal.

Debe hacerse explícito que el método no incorpora ajustes intra-anuales ni interpolaciones dentro del año calendario; la unidad temporal mínima de análisis es el año completo.