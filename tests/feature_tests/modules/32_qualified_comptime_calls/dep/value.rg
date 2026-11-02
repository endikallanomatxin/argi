identity := #(.t: Type) (.value: t) -> (.result: t) {
    result = value
}

Box := #(.t: Type) (.value: t)

BoxInitArgs: Type = #(.t: Type) (.value: t)

implement#(.t: Type) Init#(Box#(.t: t), BoxInitArgs#(t)) (
    .Result : Type = Box#(.t: t)

    .init = BoxInitArgs#(t) -> (.result: Result) {
        _init_value ::= ~value

        result = (.value = _init_value)
    }
)
