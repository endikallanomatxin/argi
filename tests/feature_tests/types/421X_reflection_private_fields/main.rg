Secret := (._value: Int32)

field := #(.T: Type) (.name: StringView, .context: Int32) -> (.result: T) { result = 0 }

main := () -> () {
    context: Int32 = 0
    value ::= construct_record#(Secret, field)(.context = context)
}
