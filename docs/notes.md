# Notas

La opción de compilación `-fno-omit-frame-pointer` evita que el compilador elimine el puntero de marco (*frame pointer*).

El puntero de marco es un registro que ayuda a seguir la cadena de llamadas de las funciones durante la ejecución. Conservarlo permite que herramientas como depuradores y perfiladores reconstruyan más fácilmente el seguimiento de la pila (*stack trace*), aunque puede introducir una pequeña penalización de rendimiento.

Por tanto, «to preserve symbols and frame pointers» significa:

- `-g`: conserva información y símbolos para depuración.
- `-fno-omit-frame-pointer`: conserva el puntero de marco.
- Esto facilita identificar qué funciones estaban ejecutándose y analizar su coste.

## Alternativa A con reducción por arrays

En la variante de simetría por pares se procesa cada pareja de partículas una sola vez, usando que la fuerza de $i$ sobre $j$ es la opuesta de la de $j$ sobre $i$. Así se reduce el trabajo aritmético al mínimo: $N(N-1)/2$ evaluaciones.

Sin embargo, cada hilo necesita un array privado de tamaño $N \times 3$ durante la reducción: tres componentes para la aceleración de cada una de las $N$ partículas. Al terminar el trabajo, OpenMP debe combinar los arrays parciales de todos los hilos mediante una reducción, lo que añade coste de memoria y comunicación entre hilos.

Además, al procesar una pareja $(i,j)$ se actualizan las aceleraciones tanto de $\mathbf{a}_i$ como de $\mathbf{a}_j$. Estos accesos corresponden a posiciones que no siguen necesariamente un orden consecutivo y, combinados con la reducción, dificultan que el compilador agrupe varias iteraciones para ejecutar instrucciones SIMD.

En resumen, esta estrategia minimiza los cálculos, pero a costa de más memoria, una reducción global entre hilos y menos oportunidades de vectorización.

## Alternativa B, por partículas con SIMD

En este enfoque, cada hilo calcula la aceleración completa de las partículas que tiene asignadas mediante

$$
\mathbf{a}_i=\sum_{j\neq i}\mathbf{g}_{ij}.
$$

Para ello acumula localmente las contribuciones de todas las demás partículas y escribe únicamente en $\mathbf{a}_i$. Como cada partícula pertenece a un solo hilo, dos hilos no modifican simultáneamente la misma posición y desaparecen las data races.

El bucle interior se divide en los intervalos $[0,i)$ y $[i+1,N)$ para evitar comprobar la condición $j\neq i$ en cada iteración. De este modo, sus accesos son más regulares y el compilador puede vectorizarlas con `#pragma omp simd`.

Aunque cada pareja se evalúa dos veces (se calculan tanto $i$ sobre $j$ como $j$ sobre $i$, para un total de $N(N-1)$ interacciones) ya no es necesario conservar un array parcial por hilo ni combinar esos arrays mediante una reducción al final. Por eso esta variante elimina las data races, el coste de la reducción y los buffers auxiliares por hilo.

En resumen, realiza más operaciones aritméticas, pero obtiene código más simple, contiguo, vectorizable y con menor coste de sincronización.

## Alternativa C, Bloques y vectores ARM SVE de 512 bits

«filling one 512-bit ARM SVE vector» indica que cada bloque o *strip* contiene 8 partículas porque sus coordenadas se representan normalmente con valores `double` de 64 bits:

$$
8 \times 64\ \text{bits} = 512\ \text{bits}.
$$

ARM SVE puede aplicar una misma instrucción a todos los elementos de un vector. Así, un registro vectorial de 512 bits procesa simultáneamente los datos correspondientes a 8 partículas, uno en cada *lane* o carril. El hilo procesa bloques de este tamaño para aprovechar al máximo la unidad vectorial.

En este caso, los 8 elementos no corresponden necesariamente a ocho componentes de una sola partícula, sino a una misma componente —por ejemplo, la coordenada $x$— de ocho partículas distintas. Los buffers Structure-of-Arrays (SoA) almacenan juntas todas las coordenadas $x$, después todas las $y$ y así sucesivamente, lo que favorece estos accesos vectoriales contiguos.
