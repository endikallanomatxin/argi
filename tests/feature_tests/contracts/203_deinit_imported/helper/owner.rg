Owner := (.value: Int32, .counter: $&Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { self&.counter&= self&.counter&+ 1 }
)
