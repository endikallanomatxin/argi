Record := (.value: Int32)

field := #(.T: Type) (.name: StringView, .context: Int32) -> (.result: Bool) { result = false }

main := () -> () {
    context: Int32 = 0
    value ::= construct_record#(Record, field)(.context = context)
}
