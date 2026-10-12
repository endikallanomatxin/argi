Copy#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))

implement Copy#(Int32)(.copy = (.value: Int32) -> (.result: Int32) { result = value })

copy#(.T: Type) := (.value: T) -> (.result: T) { result = value }

main := () -> () {
    value: Int32 = 7
    copy(value)
}
