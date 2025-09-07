## Comptime

(from zig and jai)

Permite hacer:
- Metaprogramming / macros, pero usando el mismo lenguaje.
	This is particularly useful for building efficient and flexible abstractions.

Lo vamos a hacer con # (inspirado en Jai):

https://github.com/Ivo-Balbaert/The_Way_to_Jai/blob/main/book/26A_Metaprogramming.md

Sí:

- `name#(.param = value)` to define generics that will be monomorphized at compile time.

- `#run` para ejecutar código en tiempo de compilación.

- `#import` para importar código de otros archivos, como un include en C.

- `#is_compile_time` para comprobar si el código se está ejecutando en tiempo de compilación.

- `#typeof` para obtener el tipo de una variable o expresión en tiempo de compilación.

    Cuando se aplica a un abstract, como este se monomorfiza, se puede resolver.

- `#if` para condicionales en tiempo de compilación, como en C.
    #if is tested at compile-time. When its condition returns true, that block of code is compiled, otherwise it is not compiled.
    No es lo mismo que `#run if (...) { ... }`, que se ejecuta en tiempo de compilación.

- `#atcalls` para ejecutar código en tiempo de compilación en cada llamada a
    una función. Sirve para validar argumentos y dar errores en tiempo de
    compilación, por ejemplo.

    Igual todas las funciones corridas en tiempo de compilación deberían
    devolver un error.

    >[!TODO]
    >Pensar en una forma de usar esto para que las librerías puedan levantar
    >errores de compilación o avisos en el lsp cuando no se usan bien.

>[!IDEA] Ergonomy for allocator, stdio, async...
> #bringsystemallocator, #bringsystemstdo, #bringsystemasync
> When the file is saved, the necessary declarations will be modified to bring
> the required system resource.
> It deletes itself at save time.
>
> (Aunque eso mas que compile time es como save time) Igual podría plantearse
> una version distinta del #, que en lugar de al compilar, sea al
> guardar/analizar con el lsp. y sirva para macros de auto-reescritura del
> archivo al guardar


No se:

- `#maintain` para decirle que las variables que tomaron un valor en tiempo de
compilación lo mantengan.

- `#code`

No me gusta:

- `#insert` es un poco como macros, igual demasiado sucio que use strings.


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


> [!CHECK]
> En un video de entrevista al de Odin y al de Elixir, de Primeagen y TJ,
> ginger bill dice que la metaprogramación suele reflejar carencias del
> lenguaje y que cuando se usa, el programa se vuelve muy difícil de debugear.
> Así que igual es interesante ver qué pasa con ello en Zig y Jai antes de
> implementarlo.


