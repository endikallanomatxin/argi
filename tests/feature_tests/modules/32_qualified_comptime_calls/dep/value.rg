identity := #(.t: Type) (.value: t) -> (.result: t) {
    result = value
}

Box := #(.t: Type) (.value: t)

implement#(.t: Type) Init#(Box#(.t: t)) (
    .init = (.value: t) -> (.result: Box#(.t: t)) {
        _init_value ::= ~value

        result = (.value = _init_value)
    }
)
