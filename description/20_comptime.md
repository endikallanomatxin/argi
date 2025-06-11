## Comptime

(from zig and jai)

Permite hacer:
- Metaprogramming / macros, pero usando el mismo lenguaje.
	This is particularly useful for building efficient and flexible abstractions.

Lo vamos a hacer con # (inspirado en Jai):

- `#run` para ejecutar código en tiempo de compilación.
- `#atcalls` para ejecutar código en tiempo de compilación en cada llamada a
una función. Sirve para validar argumentos y dar errores en tiempo de
compilación, por ejemplo.

Igual todas las funciones corridas en tiempo de compilación deberían devolver un error.



>[!TODO]
>Pensar en una forma de usar esto para que las librerías puedan levantar
>errores de compilación o avisos en el lsp cuando no se usan bien.

> Había descartado la idea de que comptime se use para hacer generics y
> interfaces, pero igual merece la pena darle la vuelta. El ejemplo que enseña
> ThePrimeagen sobre quak() es interesante.
> https://youtu.be/Vxq6Qc-uAmE?si=-K0XTw2lAMFC10tM
