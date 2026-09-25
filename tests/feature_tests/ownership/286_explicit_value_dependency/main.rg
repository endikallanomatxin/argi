Owner : Type = (
    .number: Int32
)

deinit(.self: $&Owner) -> () := {
}

main() -> (.status_code: Int32) := {
    owner :: Owner = (.number = 7)
    dependent ::= depend_on#(.t: Int32)(.value = 12, .on = &owner).result
    status_code = dependent - 12
    deinit(.self = $&owner)
}
