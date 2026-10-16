-- Multiple generic parameters (functions)

pick_first#(.a: Type, .b: Type)(.x: a, .y: b) -> (.r: a) := {
    r = x
}

main() -> (.status_code: Int32) := {
    status_code = pick_first#(.a: Int32, .b: UnicodeScalar)(.x = 41, .y = 'Z').r + 1
}
