identity#(.t: Type)(.value: t) -> (.result: t) := {
    result = value
}

Box#(.t: Type) : Type = (.value: t)

Box init#(.t: Type)(.value: t) -> (.result: Box#(.t: t)) := {
    result = (.value = value)
}
