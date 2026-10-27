Counter := (.count: Int32)

Child := (.counter: $&Counter)

Parent := (.child: Child, .missing: Int32)

implement Deinit#(Child) (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

implement Deinit#(Parent) (
    .deinit = (.self: $&Parent) -> () {
        self&.child.counter&.count = self&.child.counter&.count + 10
        deinit(.self = $&self&.child)
    }
)

implement Init#(Child) (
    .init = (.counter: $&Counter) -> (.result: Child) {
        result = (.counter = counter)
    }
)

build_partial := (.counter: $&Counter, .early: Bool) -> () {
    parent :: Parent
    parent.child = Child(.counter = counter)
    if early { return }
    parent.missing = 1
}

replace_partial := (.counter: $&Counter) -> () {
    parent :: Parent
    parent.child = Child(.counter = counter)
    child := $&parent.child
    child&= Child(.counter = counter)
    parent.missing = 1
}

build_conditional := (.counter: $&Counter, .complete: Bool) -> () {
    parent :: Parent
    parent.child = Child(.counter = counter)
    if complete { parent.missing = 1 }
}

build_conditional_child := (.counter: $&Counter, .present: Bool) -> () {
    parent :: Parent
    if present { parent.child = Child(.counter = counter) }
}

probe := () -> (.result: Int32) {
    counter :: Counter = (.count = 0)
    build_partial(.counter = $&counter, .early = true)
    if counter.count != 1 { abort }
    build_partial(.counter = $&counter, .early = false)
    if counter.count != 12 { abort }
    index :: Int32 = 0
    while index < 2 {
        outer :: (.parent: Parent, .missing: Int32)
        outer.parent.child = Child(.counter = $&counter)
        index = index + 1
    }
    if counter.count != 14 { abort }
    {
        outer :: (.parent: Parent, .missing: Int32)
        outer.parent.child = Child(.counter = $&counter)
        outer.parent.missing = 1
    }
    if counter.count != 25 { abort }
    build_conditional(.counter = $&counter, .complete = false)
    build_conditional(.counter = $&counter, .complete = true)
    if counter.count != 37 { abort }
    build_conditional_child(.counter = $&counter, .present = false)
    build_conditional_child(.counter = $&counter, .present = true)
    if counter.count != 38 { abort }
    replace_partial(.counter = $&counter)
    if counter.count != 50 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    if #run () -> (.value: Int32) { value = probe() } != 42 { abort }
    status_code = probe()
}
