Number: CUnion = (.first: Int32, .second: Int32)

Alias := #(.T: Type) T

field := #(.T: Type) (.name: StringView, .context: Int32) -> (.result: T) { result = 0 }

main := () -> () {
    context: Int32 = 0
    value ::= construct_record#(Alias#(Number), field)(.context = context)
}
