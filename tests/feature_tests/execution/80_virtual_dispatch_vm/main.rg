Counter: Type = (.value: Int32)

Counting#(.State: Type): Contract = (
    .bump : (.self: $&State, .amount: Int32) -> () where {}
    .read : (.self: &State) -> (.result: Int32) where {}
)

implement Counting#(Counter) (
    .bump = (.self: $&Counter, .amount: Int32) -> () {
        self&.value = self&.value + amount
    }
    .read = (.self: &Counter) -> (.result: Int32) {
        result = self&.value
    }
)

counted := () -> (.result: Int32) {
    counter :: Counter = (.value = 7)
    erased ::= to_virtual#(.contract: Counting)(.value = $&counter)
    Counting#().bump($&erased, 35)
    result = Counting#().read(&erased).result
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run counted()
    if compiled != 42 { abort }
    #if counted() == 42 {
        status_code = counted()
    } else {
        abort
    }
}
