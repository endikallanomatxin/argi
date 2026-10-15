First#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))

Second#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))

implement First#(Int32)(.copy = (.value: Int32) -> (.result: Int32) { result = value })
implement Second#(Int32)(.copy = (.value: Int32) -> (.result: Int32) { result = value })

wrapper#(.T: Type) := (.value: T) -> (.result: T) { result = copy(value) }

main := () -> () {
    value: Int32 = 7
    wrapper(value)
}
