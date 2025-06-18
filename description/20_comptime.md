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

	Igual todas las funciones corridas en tiempo de compilación deberían
	devolver un error.

    >[!TODO]
    >Pensar en una forma de usar esto para que las librerías puedan levantar
    >errores de compilación o avisos en el lsp cuando no se usan bien.


- `#import` para importar código de otros archivos, como un include en C.


- `#typeof` para obtener el tipo de una variable o expresión en tiempo de compilación.

    Cuando se aplica a un abstract, como este se monomorfiza, se puede resolver.


> [!CHECK]
> Había descartado la idea de que comptime se use para hacer generics y
> interfaces, pero igual merece la pena darle la vuelta. El ejemplo que enseña
> ThePrimeagen sobre quak() es interesante.
> https://youtu.be/Vxq6Qc-uAmE?si=-K0XTw2lAMFC10tM
> Eso sí me gusta, pero no me gusta que tengas que usar anytype, que es
> demasiado opaco y no le dejas claro al usuario qué tipo de datos espera.
> Además con eso no cumples todo lo que necesitas de las generics.
>
> La mayor discrepancia: para que los tipos que devuelven las funcones puedan
> considerarse equivalentes, hay que hacer structural typing, en lugar de nominal.
> Eso es una mierda.

https://www.scottredig.com/blog/bonkers_comptime/
