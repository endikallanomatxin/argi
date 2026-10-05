library ::= import ("./library")

Reasons: Type = (..unavailable)

Pair#(.left: Type, .right: Type): Type = (.left: left, .right: right)

checked(.value: Int32) -> (.result: Errable#(Int32, Reasons)) := {
    if value < 0 {
        result = ..error(.reason = ..unavailable)
        return
    }

    result = ..ok value
}

echo#(.t: Type)(.value: t) -> (.result: Errable#(t, Reasons)) := {
    result = ..ok value
}

open_echo#(.t: Type)(.value: t) -> (.result: Errable#(t)) := {
    result = ..ok value
}

ReadValue#(.t: Type): Abstract = (
    read(.self: &Self) -> (.value: t)
)

IntegerValue: Type = (.value: Int32)

IntegerValue implements ReadValue#(Int32)

read(.self: &IntegerValue) -> (.value: Int32) := { value = self&.value }

read_value#(.t: Type, .source: Type: ReadValue#(t))(.self: &source) -> (.value: t) := {
    value = read(.self = self).value
}

main() -> (.status_code: Int32 = 0) := {
    value ::= unwrap_or_abort(.value = checked(42)).result
    if value != 42 { abort }

    generic ::= unwrap_or_abort(.value = echo(7)).result
    if generic != 7 { abort }

    match open_echo(6) {
        ..ok value { if value != 6 { abort } }
        ..error _ { abort }
    }

    borrowed ::= IntegerValue(5)
    if read_value#(Int32, IntegerValue)(.self = &borrowed).value != 5 { abort }

    imported: library.Box#(Int32) = (.value = 13)
    if library.read_box(&imported).value != 13 { abort }

    pair: Pair#(Int32, Bool) = (.left = 3, .right = true)
    mixed: Pair#(Int32, .right: Bool) = (.left = 4, .right = false)
    if pair.left != 3 or mixed.right { abort }

    array: Array#(2, Int32) = (11, 12)
    if array[1] != 12 { abort }

    mixed_result: Errable#(Int32, .reasons: Reasons) = ..ok 8
    if unwrap_or_abort(.value = mixed_result).result != 8 { abort }

    nested: Pair#(Errable#(Int32, Reasons), Bool) = (.left = ..ok 9, .right = true)
    if unwrap_or_abort(.value = nested.left).result != 9 { abort }

    match checked(-1) {
        ..ok _ { abort }
        ..error error { if error.reason != ..unavailable { abort } }
    }
}
