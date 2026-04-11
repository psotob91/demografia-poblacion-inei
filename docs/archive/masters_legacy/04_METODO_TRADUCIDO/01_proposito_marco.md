0. Propósito y alcance
0.1 Objetivo del componente demográfico

El componente demográfico tiene como finalidad construir una base poblacional analítica, reproducible y conceptualmente consistente, que sirva como denominador común para las estimaciones de carga de enfermedad desagregadas por año calendario, edad simple, sexo y ubicación geográfica. En este contexto, la función principal del componente no es producir una nueva proyección demográfica nacional, sino transformar y armonizar insumos poblacionales oficiales en una estructura utilizable para análisis epidemiológicos comparables entre estratos y a lo largo del tiempo. Esta formulación es consistente con el propósito declarado del repositorio de generar un dataset canónico de población para uso downstream en mortalidad, AVP, morbilidad y carga de enfermedad.

Desde una perspectiva epidemiológica, este componente permite que los numeradores de eventos, defunciones o años perdidos se expresen sobre denominadores definidos de manera homogénea. Desde una perspectiva bioestadística, el componente establece un contrato analítico explícito sobre la unidad de observación y sobre las restricciones mínimas que deben cumplir las estimaciones poblacionales para ser usadas en agregación, estandarización y comparación temporal. La unidad analítica final implementada corresponde a combinaciones únicas de año, edad, sexo y ubicación, con conteos absolutos de población por celda.

0.2 Rol dentro del estudio de carga de enfermedad

En estudios de carga de enfermedad, la población cumple un papel estructural como denominador de tasas y como base de agregación para múltiples indicadores. En este repositorio, el componente demográfico está diseñado para integrarse con análisis downstream de mortalidad, años de vida perdidos y otros componentes de carga, proporcionando una malla poblacional única sobre la cual puedan proyectarse o compararse resultados de diferentes módulos analíticos. El README del proyecto establece explícitamente este propósito downstream.

Metodológicamente, esto implica que la población aquí generada debe leerse como una población de referencia operativa para análisis epidemiológicos, no como un ejercicio autónomo de demografía formal. En otras palabras, su valor radica en la consistencia analítica, la trazabilidad y la utilidad para el cálculo de indicadores, más que en reemplazar las fuentes oficiales originales. Esta precisión debe hacerse explícita para evitar una interpretación sobredimensionada del componente.

0.3 Alcance y exclusiones

El alcance del componente comprende la construcción de conteos poblacionales por edad simple, sexo, ubicación y año calendario dentro de una cobertura temporal predefinida, con reglas explícitas para armonizar estructuras, extender la cola etaria y construir agregados nacionales alternativos cuando se requiere consistencia jerárquica. La especificación formal del dataset final incluye años entre 1995 y 2030, edades entre 0 y 110 años, sexo final restringido a masculino y femenino, y ubicaciones departamentales más una categoría nacional oficial.

El componente también contempla una segunda representación analítica del nivel nacional basada en la suma exacta de departamentos, concebida para usos donde la consistencia jerárquica estricta es prioritaria. Esta coexistencia de dos definiciones nacionales no debe entenderse como contradicción, sino como respuesta a dos necesidades analíticas distintas: preservar la fuente institucional tal como se publica y, simultáneamente, disponer de un agregado perfectamente aditivo para análisis subnacionales. Esta decisión ya ha sido reconocida como una convención metodológica relevante que debe mantenerse explícitamente documentada.

Quedan fuera del alcance de este componente: la estimación primaria de fecundidad, mortalidad o migración; la reconstrucción demográfica mediante métodos clásicos de componentes; la cuantificación formal de incertidumbre poblacional; y la validación externa exhaustiva contra fuentes demográficas alternativas. También quedan fuera del alcance los cálculos finales de AVP, AVISA u otros indicadores de carga, aunque la población producida aquí esté destinada a alimentar esos análisis. Este encuadre es consistente con el alcance general del proyecto, que prioriza documentar el repositorio y su papel dentro de un ecosistema mayor, sin reescribir el código ni extender artificialmente sus pretensiones metodológicas.

1. Marco conceptual
1.1 Definición de población en estudios de carga de enfermedad

En el contexto de estudios de carga de enfermedad, la población se define como el número de personas pertenecientes a una unidad demográfica específica en un año calendario dado, estratificada por edad, sexo y ubicación geográfica. Bajo esta definición, la población actúa como denominador de tasas y como base de agregación para métricas que combinan frecuencia de eventos y estructura demográfica. La estructura final implementada en este repositorio responde precisamente a esa lógica: cada observación representa un conteo absoluto de personas correspondiente a una combinación única de año, edad simple, sexo y ubicación.

Esta definición operativa tiene dos implicancias. Primero, la población aquí estimada no representa riesgo individual ni exposición acumulada, sino tamaño poblacional por estrato. Segundo, su utilidad principal es permitir comparabilidad interna entre módulos analíticos que comparten la misma estratificación. Por ello, el componente demográfico debe entenderse como un insumo transversal y no como un resultado final autosuficiente.

1.2 Unidad analítica (edad, sexo, ubicación, año)

La unidad analítica del componente está definida por cuatro dimensiones: edad, sexo, ubicación geográfica y año calendario. Esta estructura constituye la llave lógica del dataset final y expresa la granularidad mínima a la cual se consideran válidos los conteos poblacionales. La spec del repositorio formaliza esta estructura mediante la clave primaria compuesta por year_id, age, sex_id y location_id, y exige que la variable de resultado sea un conteo entero no negativo.

Conceptualmente, esta elección es adecuada para estudios de carga de enfermedad por al menos tres razones. En primer lugar, la edad simple permite compatibilidad con desagregaciones posteriores y con reagrupaciones flexibles hacia bandas etarias más amplias. En segundo lugar, la estratificación por sexo permite alinear el denominador con fuentes de eventos que suelen reportarse al menos por masculino y femenino. En tercer lugar, la estratificación geográfica por departamento y nacional permite producir estimaciones tanto subnacionales como agregadas.

Debe hacerse explícito, sin embargo, que esta unidad analítica responde a una finalidad epidemiológica-operativa y no necesariamente a la forma original en que todas las fuentes demográficas publican sus datos. El método, por tanto, incluye un proceso de armonización para llevar la información fuente hacia esta unidad estándar. También debe dejarse claro que, aunque en etapas intermedias puede existir información total por sexo, el resultado final queda restringido a masculino y femenino, en consonancia con el contrato analítico definido para el dataset final. Esta convención local forma parte del método real y no debe omitirse en el anexo.

1.3 Relación con tasas, AVP y AVISA

La relación entre población y métricas de carga de enfermedad es fundamentalmente denominacional y estructural. Las tasas de incidencia, prevalencia, mortalidad u otros eventos requieren una población de referencia que comparta la misma estratificación básica. Asimismo, los Años de Vida Perdidos (AVP) y los Años de Vida Saludable Perdidos (AVISA) dependen directa o indirectamente de la estructura poblacional para su cálculo, estandarización o interpretación comparativa. El repositorio declara explícitamente que la población producida está destinada a estos usos downstream.

En términos conceptuales, si 
𝐸
𝑎
,
𝑠
,
𝑙
,
𝑡
E
a,s,l,t
	​

 representa un numerador de eventos en edad 
𝑎
a, sexo 
𝑠
s, ubicación 
𝑙
l y año 
𝑡
t, y 
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

 representa la población del mismo estrato, entonces una tasa específica se expresa como:

𝑟
𝑎
,
𝑠
,
𝑙
,
𝑡
=
𝐸
𝑎
,
𝑠
,
𝑙
,
𝑡
𝑃
𝑎
,
𝑠
,
𝑙
,
𝑡
r
a,s,l,t
	​

=
P
a,s,l,t
	​

E
a,s,l,t
	​

	​


Esta ecuación no agota la complejidad de los indicadores de carga, pero sí resume el papel mínimo e indispensable del componente demográfico: proveer un denominador coherente para el estrato analítico de interés. El valor metodológico de este componente no reside, por tanto, en modelar directamente la enfermedad, sino en asegurar que la base poblacional usada para cuantificarla sea consistente entre niveles geográficos, grupos de edad, sexos y años.

Para mantener coherencia conceptual, también debe explicitarse que este componente no produce por sí mismo tasas, AVP ni AVISA. Produce únicamente la base poblacional necesaria para esos cálculos. Esa distinción es importante, porque evita atribuir al componente propiedades analíticas que en realidad pertenecen a módulos posteriores del estudio de carga de enfermedad.