8. Consistencia interna y coherencia demográfica
8.1 Coherencia por edad

El método incorpora criterios de coherencia interna a lo largo de la dimensión etaria, con el objetivo de asegurar que la distribución de la población sea demográficamente plausible y analíticamente estable.

En particular, se espera que:

la población sea no negativa para todas las edades;
la transición entre edades consecutivas no presente discontinuidades abruptas no justificadas;
en edades avanzadas, la población siga una tendencia no creciente.

La coherencia por edad se garantiza mediante la combinación de datos observados en edades tempranas y medias, junto con el modelamiento en la cola etaria (sección 6), que impone suavidad y monotonicidad.

Debe hacerse explícito que este criterio no implica validar la exactitud de la estructura etaria frente a fuentes externas, sino asegurar consistencia interna dentro del dataset analítico.

8.2 Coherencia por sexo

La coherencia por sexo se refiere a la consistencia de las distribuciones poblacionales entre hombres y mujeres a lo largo de las edades y años.

El método asume que:

la suma de las poblaciones por sexo reproduce la población total cuando esta se encuentra disponible;
no existen categorías ambiguas o inconsistentes de sexo en el dataset final;
las diferencias entre sexos reflejan patrones demográficos plausibles (por ejemplo, mayor supervivencia femenina en edades avanzadas).

No se aplican ajustes explícitos para forzar relaciones esperadas entre sexos (como razones de masculinidad específicas), pero se espera que la fuente original ya incorpore dichas características.

Debe hacerse explícito que cualquier sesgo o inconsistencia en la distribución por sexo proviene de la fuente de datos y no es corregido en este componente.

8.3 Coherencia geográfica

La coherencia geográfica implica que las poblaciones subnacionales (departamentales) sean consistentes entre sí y con el total nacional, bajo las definiciones establecidas en la sección 7.

El método garantiza:

que cada unidad geográfica esté definida de manera única y consistente en el tiempo;
que no existan solapamientos entre unidades;
que la suma de unidades subnacionales sea interpretable como un agregado válido.

Sin embargo, dado que se mantienen dos definiciones de población nacional (oficial y aditiva), la coherencia geográfica puede depender de la elección del denominador. La coherencia estricta (aditiva) se garantiza únicamente cuando se utiliza la población nacional derivada de la suma de departamentos.

Debe hacerse explícito que no se realizan ajustes de reconciliación espacial adicionales (por ejemplo, redistribución proporcional), lo que implica que las discrepancias observadas reflejan directamente la estructura de la fuente.

8.4 Consistencia jerárquica

La consistencia jerárquica se refiere a la relación entre diferentes niveles de agregación (edad, sexo, ubicación) y a la capacidad del dataset de mantener identidades contables entre ellos.

Formalmente, para cualquier nivel de agregación válido, se espera que:

∑
𝑎
∈
𝐴
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
=
𝑃
𝑠
,
𝑙
,
𝑡
,
∑
𝑠
∈
𝑆
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
=
𝑃
𝑎
,
𝑙
,
𝑡
,
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
=
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
a∈A
∑
	​

P
a,s,l,t
	​

=P
s,l,t
	​

,
s∈S
∑
	​

P
a,s,l,t
	​

=P
a,l,t
	​

,
l∈L
∑
	​

P
a,s,l,t
	​

=P
a,s,t
(nat_add)
	​


donde 
𝐴
A, 
𝑆
S y 
𝐿
L representan los conjuntos de edades, sexos y ubicaciones, respectivamente.

Estas identidades se cumplen estrictamente en el dataset analítico, al menos bajo la definición aditiva de población nacional. Esto permite:

realizar agregaciones y desagregaciones sin pérdida de coherencia;
integrar el componente demográfico en modelos jerárquicos;
validar resultados intermedios en el pipeline de carga de enfermedad.

Debe hacerse explícito que la consistencia jerárquica es una propiedad construida del dataset analítico y no necesariamente una característica de la fuente original.

9. Supuestos del método
9.1 Supuestos sobre los datos de entrada

El método descansa sobre varios supuestos fundamentales respecto a los datos poblacionales utilizados:

Validez de la fuente oficial:
se asume que las estimaciones poblacionales proporcionadas por el organismo oficial son la mejor aproximación disponible al tamaño y estructura de la población.
Comparabilidad temporal:
se asume que las estimaciones son comparables entre años, es decir, que no existen cambios metodológicos sustanciales que introduzcan discontinuidades no observadas.
Consistencia geográfica:
se asume que las unidades geográficas son comparables en el tiempo y que cualquier cambio administrativo es adecuadamente reflejado en la fuente.
Calidad suficiente en edades medias:
se asume que las estimaciones en edades intermedias (por ejemplo, 30–70 años) son suficientemente confiables como para servir de base para procesos de modelamiento en edades avanzadas.

Estos supuestos no son verificados explícitamente dentro del método, sino que se adoptan como condiciones necesarias para su aplicación.

9.2 Supuestos del modelamiento

El componente de modelamiento de edades avanzadas introduce supuestos adicionales:

Forma funcional suave:
la relación entre edad y logaritmo de la población es continua y puede aproximarse mediante funciones suaves.
Decrecimiento en edades avanzadas:
la población disminuye con la edad a partir de un umbral determinado.
Extrapolación válida:
la tendencia observada en edades 70–79 es representativa de la tendencia en edades superiores.
Independencia entre estratos:
las distribuciones por sexo, ubicación y año pueden modelarse de manera independiente sin pérdida sustantiva de información.

Estos supuestos son necesarios para la operatividad del modelo, pero deben ser considerados aproximaciones que pueden no sostenerse en todos los contextos.

9.3 Supuestos estructurales del enfoque

Además de los supuestos sobre datos y modelamiento, el método incorpora supuestos estructurales que definen su marco operativo:

Edad como variable discreta completa (0–110):
se asume que la población puede representarse completamente en este rango, independientemente de la disponibilidad de datos observados en todos los puntos.
Exclusión de incertidumbre explícita:
el método trabaja con estimaciones puntuales, asumiendo implícitamente que la incertidumbre en la población es secundaria frente a otras fuentes de variabilidad en el análisis de carga de enfermedad.
Separación entre componente demográfico y epidemiológico:
se asume que la población puede ser tratada como un insumo fijo, independiente de los modelos de incidencia, prevalencia o mortalidad.
Neutralidad analítica:
el componente demográfico no introduce ajustes para mejorar la concordancia con resultados epidemiológicos (por ejemplo, tasas), sino que se mantiene como una representación independiente de la población.

Estos supuestos definen el alcance y las limitaciones del método, y deben ser considerados al interpretar los resultados derivados del uso de este componente.