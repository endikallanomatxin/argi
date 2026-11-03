Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
worker := #(.T: Type) (.value: T) -> (.result: T): CFunction { result = value }
make := #(.T: Type) () -> (.result: Callback) { result = Callback(.function = worker#(T)) }
main := () -> () { callback ::= make#(CShort)() _ = callback }
