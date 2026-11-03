Callback() -> (): CFunctionPointer(.isolated = true)
initial :: Int32 = 0
stored :: $&Int32 = $&initial
helper := () -> () { stored&= stored&+ 1 }
worker := () -> (): CFunction { helper() }
main := () -> () { callback ::= Callback(.function = worker) _ = callback }
