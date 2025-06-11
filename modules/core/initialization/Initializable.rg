Initializable : Abstract = [
    init(t:==Initializable, ...) : Initializable
    deinit($&i:Initializable, ...)
    ---
    Cuando una variable no se ha keepeado, al cerrar el scope se desinicializa.
    All types are expected to be initializable.
    Si no, hay una implementación por defecto para structs y tipos básicos, así que se encarga eso.
    ---
]
