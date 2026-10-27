Counter := (.count: UIntNative = 0)

bump := (.counter: $&Counter = reach counter) -> (.result: UIntNative) {
    counter&.count = counter&.count + 1
    result = counter&.count
}

Value := #(.Tag: Type) (.number: UIntNative)

ValueInitArgs: Type = #(.Tag: Type) (.number: UIntNative = bump())

implement#(.Tag: Type) Init#(Value#(Tag), ValueInitArgs#(Tag)) (
    .Result : Type = Value#(Tag)

    .init = ValueInitArgs#(Tag) -> (.result: Result) {
        result = (.number = number)
    }
)

main := () -> () {
    state :: Counter = (.count = 0)
    assume counter := $&state
    first ::= Value#(Int32)()
    explicit ::= Value#(Int32)(.number = 42)
    second ::= Value#(Int32)()
    if first.number != 1 or explicit.number != 42 or second.number != 2 { abort }
    if state.count != 2 { abort }
}
