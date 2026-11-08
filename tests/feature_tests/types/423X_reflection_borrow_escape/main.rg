Record := (.value: &Int32)

field := #(.T: Type) (.name: StringView, .context: &Int32) -> (.result: T) { result = context }

escape := () -> (.result: Record) {
    local: Int32 = 42
    result = construct_record#(Record, field)(.context = &local)
}

main := () -> () { escape() }
