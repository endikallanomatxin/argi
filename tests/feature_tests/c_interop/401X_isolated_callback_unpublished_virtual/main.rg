Callback() -> (.result: CInt): CFunctionPointer(.isolated = true)
Reader#(.R: Type): Contract = (
    .read: (.self: R) -> (.result: CInt) where no_access()
)
implement Reader#(&CInt) (
    .read = (.self: &CInt) -> (.result: CInt) { result = 7 }
)
worker := () -> (.result: CInt): CFunction {
    value: CInt = 7
    view ::= Virtual#(Reader)(&value)
    result = view.read().result
}
main := () -> () {
    callback ::= Callback(.function = worker)
    _ = callback
}
