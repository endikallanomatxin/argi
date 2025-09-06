-- Minimal generic function test

id #(.T: Type) (.x: T) -> (.y: T) := {
    y = x
}

main () -> (.status_code: Int32) := {
    status_code = id#(.T: Int32)(.x = 41).y + 1
}
