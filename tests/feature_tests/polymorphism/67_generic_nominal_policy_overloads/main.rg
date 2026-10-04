HasMarker: Abstract = (marker(.self: &Self) -> (.value: Int32))

Token: Type = (.id: Int32)

Token implements ImplicitlyCopyable

Plain#(.policy: Type: ImplicitlyCopyable): Type = (.policy: policy, .value: Int32)

Checked#(.policy: Type: HasMarker): Type = (.policy: policy, .value: Int32)

lookup#(.policy: Type)(.self: &Plain#(.policy: policy)) -> (.value: Int32) := {
    value = self&.value
}

lookup#(.policy: Type)(.self: &Checked#(.policy: policy)) -> (.value: Int32) := {
    value = marker(.self = &self&.policy).value
}

MarkerPolicy: Type = (.id: Int32)

MarkerPolicy implements HasMarker

marker(.self: &MarkerPolicy) -> (.value: Int32) := { value = self&.id }

make_plain() -> (.result: Errable#(.t: Plain#(.policy: Token), .reasons: (..out_of_memory))) := {
    result = ..ok Plain#(.policy: Token)(.policy = Token(.id = 1), .value = 42)
}

make_checked() -> (
        .result : Errable#(.t: Checked#(.policy: MarkerPolicy), .reasons: (..out_of_memory))
    ) := {
    result = ..ok Checked#(.policy: MarkerPolicy)(.policy = MarkerPolicy(.id = 7), .value = 42)
}

main() -> (.status_code: Int32 = 0) := {
    plain ::= unwrap_or_abort(.value = make_plain())
    if lookup#(.policy: Token)(.self = &plain).value != 42 { abort }
    if lookup(.self = &plain).value != 42 { abort }
    checked ::= unwrap_or_abort(.value = make_checked())
    if lookup#(.policy: MarkerPolicy)(.self = &checked).value != 7 { abort }
    if lookup(.self = &checked).value != 7 { abort }
}
