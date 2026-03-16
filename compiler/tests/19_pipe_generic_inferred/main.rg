id #(.t: Type) (.x: t) -> (.y: t) := {
    y = x
}

main () -> (.status_code: Int32) := {
    status_code = 42 | id(_)
}
