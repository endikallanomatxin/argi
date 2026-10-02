Owner : Type = (
    .number: Int32
)

deinit(.self: $&Owner) -> () := {
}

identity(.value: Int32) -> (.result: Int32) := {
    result = value
}

main() -> (.status_code: Int32) := {
    owner :: Owner = (.number = 7)
    dependent ::= depend_on#(.t: Int32)(.value = 12, .on = &owner).result
    forwarded ::= identity(.value = dependent).result
    deinit(.self = $&owner)
    status_code = forwarded - 12
}
