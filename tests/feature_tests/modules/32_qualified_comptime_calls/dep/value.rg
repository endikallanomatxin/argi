identity#(.t: Type)(.value: t) -> (.result: t) := {
    result = value
}

Box#(.t: Type) : Type = (.value: t)

implement#(.t: Type) Init#(Box#(.t: t), (.value: t)) (
    .Result: Type = Box#(.t: t)
    .init = (.args: (.value: t)) -> (.result: Result) {
        value ::= ~args.value

        result = (.value = value)
    }
)
