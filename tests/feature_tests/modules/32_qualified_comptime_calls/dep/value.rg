identity#(.t: Type)(.value: t) -> (.result: t) := {
    result = value
}

Box#(.t: Type) : Type = (.value: t)

init#(.t: Type)(.p: $&Box#(.t: t), .value: t) -> () := {
    p& = (.value = value)
}
