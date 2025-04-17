https://www.youtube.com/watch?v=gITmP0IWff0&list=WL&t=1252s

Hay dos algoritmos, uno que corre en tiempo lineal y otro exponencial.

Desde hace mucho que casi todos los regex usan el algoritmo malo.

Una vez se implementó que os regex pudieran tener backreferences, y ya no se podía volver atrás al algoritmo bueno.
Ahora el mundo entero usa el regex que no es muy eficiente si el tamaño de la regex es grande.


RE2 es una implementación moderna del algorimo bueno:

https://github.com/google/re2/wiki/syntax

Creo que es el que usa go.

