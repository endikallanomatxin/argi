acquire := once #(.T: Type) (.value: T) -> (.result: T) { result = value }

int_acquire := acquire#(Int32)

Acquire#(.T: Type): Contract = (.acquire_value: _)

implement Acquire#(Int32) (.acquire_value = int_acquire)

main := () -> (.status_code: Int32 = 0) {
    first ::= acquire_value(1)
    second ::= int_acquire(2)
    status_code = first + second
}
