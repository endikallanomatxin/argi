Counter: Type = (.count: Int32)

Child: Type = (.counter: $&Counter)

Parent: Type = (.child: Child, .missing: Int32)

implement Deinit#(Child) (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

implement Deinit#(Parent) (
    .deinit = (.self: $&Parent) -> () {
        abort
    }
)

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = (.count = 0)
    {
        parent :: Parent
        parent.child = Child(.counter = $&counter)
    }
    if counter.count != 1 { abort }
    status_code = 42
}
