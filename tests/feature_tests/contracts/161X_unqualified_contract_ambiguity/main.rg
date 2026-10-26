First<.T: Type>: Contract = (.copy: (.value: T) -> (.result: T))

Second<.T: Type>: Contract = (.copy: (.value: T) -> (.result: T))

implement<.T: Type> First<T> (.copy = (.value: T) -> (.result: T) { result = value })

implement Second<Int32> (.copy = (.value: Int32) -> (.result: Int32) { result = value })

main := () -> () {
    value: Int32 = 7
    copy(value)
}
