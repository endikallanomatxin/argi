# Derive macros from rust

Los más comunes son:

- Debug. Sirve para imprimir el struct.

- Clone. Sirve para hacer un deep copy del struct.

- Default. Sirve para inicializar el struct con valores por defecto.

- PartialEq. Sirve para comparar structs. (== y !=)

- PartialOrd. Sirve para comparar structs. (<, >, <=, >=)

- Eq. Sirve para comparar structs. (== y !=) (no es necesario si tienes PartialEq)


Idea:
Para que algo sea hasheable todos sus campos tienen que ser hasheables. Si esa verificación en una comptime function se puede usar para el lsp.
