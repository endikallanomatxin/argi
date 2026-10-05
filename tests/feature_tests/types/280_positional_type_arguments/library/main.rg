Box#(.t: Type): Type = (.value: t)

read_box(.self: &Box#(.t: Int32)) -> (.value: Int32) := {
    value = self&.value
}
