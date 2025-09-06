-- Minimal generic function test

id #(.t: Type) (.x: t) -> (.y: t) := {
    y = x
}

main () -> (.status_code: Int32) := {
    status_code = id#(.t: Int32)(.x = 41).y + 1
}
