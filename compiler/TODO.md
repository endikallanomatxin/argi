- Choice types: Implement

- Generics:

    - Compile time parameter inference

- Abstracts:

    - Fix: Actualmente el símbolo del abstract se registra como “tipo nominal”
    placeholder que internamente mapea a Any. Además, no se permite usar un
    abstract como tipo de símbolo si no hay defaultsto.

    - Self en salidas: extender el checker para sustituir Self también en
    retornos antes de comparar, igual que ya hacéis para entradas. Pequeño
    cambio: aplicar buildExpected… a output y comparar tras sustitución.

    - canbe/defaultsto genéricos: soportar patrones Indexable#(T) canbe
    Vector#(T) resolviendo con un mapa de sustitución (ya tenéis infra de
    sustituciones para genéricos). Esto permite que los bounds pasen al
    instanciar Vector#(Int32)

    (por ahora no trabajar más en el defaultsto, que igual lo quitamos)


