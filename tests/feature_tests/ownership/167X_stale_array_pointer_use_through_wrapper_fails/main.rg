Value : Type = (
    .items: [2]Int32
)

deinit(.self: $&Value) -> () := {
}

read_first(.p: $&[2]Int32) -> (.result: Int32) := {
    result = p&[0]
}

main() -> (.status_code: Int32) := {
    source :: Value = (.items = (7, 8))
    pointer ::= $&source.items
    deinit(.self = $&source)
    source = (.items = (9, 10))
    status_code = read_first(.p = pointer).result
    deinit(.self = $&source)
}
