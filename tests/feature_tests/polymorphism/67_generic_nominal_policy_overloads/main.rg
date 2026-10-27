Lookup#(.Value: Type): Contract = (
    .lookup : (.self: &Value) -> (.value: Int32)
)

HasMarker#(.Participant: Type): Contract = (.marker: (.self: &Participant) -> (.value: Int32))

Token := (.id: Int32)

implement ImplicitlyCopyable#(Token) ()

Plain := #(.policy: Type: ImplicitlyCopyable) (.policy: policy, .value: Int32)

Checked := #(.policy: Type: HasMarker) (.policy: policy, .value: Int32)

_plain_lookup := #(.policy: Type) (.self: &Plain#(.policy: policy)) -> (.value: Int32) {
    value = self&.value
}

_checked_lookup := #(.policy: Type) (.self: &Checked#(.policy: policy)) -> (.value: Int32) {
    value = marker(.self = &self&.policy).value
}

implement#(.policy: Type: ImplicitlyCopyable) Lookup#(Plain#(.policy: policy)) (
    .lookup = _plain_lookup
)

implement#(.policy: Type: HasMarker) Lookup#(Checked#(.policy: policy)) (
    .lookup = _checked_lookup
)

MarkerPolicy := (.id: Int32)

implement HasMarker#(MarkerPolicy) (.marker = _impl_marker_MarkerPolicy)

_impl_marker_MarkerPolicy := (.self: &MarkerPolicy) -> (.value: Int32) { value = self&.id }

make_plain := () -> (.result: Errable#(.t: Plain#(.policy: Token), .reasons: (..out_of_memory))) {
    result = ..ok Plain#(.policy: Token)(.policy = Token(.id = 1), .value = 42)
}

make_checked := () -> (
    .result: Errable#(.t: Checked#(.policy: MarkerPolicy), .reasons: (..out_of_memory))
) {
    result = ..ok Checked#(.policy: MarkerPolicy)(.policy = MarkerPolicy(.id = 7), .value = 42)
}

main := () -> (.status_code: Int32 = 0) {
    plain ::= unwrap_or_abort(.value = make_plain())
    if Lookup#(Plain#(.policy: Token)).lookup(.self = &plain).value != 42 { abort }
    if lookup(.self = &plain).value != 42 { abort }
    checked ::= unwrap_or_abort(.value = make_checked())
    if Lookup#(Checked#(.policy: MarkerPolicy)).lookup(.self = &checked).value != 7 { abort }
    if lookup(.self = &checked).value != 7 { abort }
}
