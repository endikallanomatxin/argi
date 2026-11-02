Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

exercise := () -> (.result: Int32) {
    counter :: Counter = Counter()
    {
        sentinel ::= Resource(.counter = $&counter)
        outer :: Int32 = 0
        while outer < 2 {
            outer = outer + 1
            resource ::= Resource(.counter = $&counter)
            defer { counter.count = counter.count + 100 }
            inner :: Int32 = 0
            while inner < 3 {
                nested ::= Resource(.counter = $&counter)
                inner = inner + 1
                if inner == 1 { continue }
                if inner == 2 { break }
            }
            if outer == 1 { continue }
            break
        }
    }
    result = counter.count
}

main := () -> (.status_code: Int32 = 0) {
    if exercise() != 207 { abort }
    computed ::= #run () -> (.value: Int32) { value = exercise() }
    if computed != 207 { abort }
}
