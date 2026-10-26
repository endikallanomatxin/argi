drops :: Int32 = 0

record_drop := (.amount: Int32) -> () { drops = drops + amount }

Box := <.t: Type> (.value: t)

Other := (.value: Int32)

implement<.t: Type> Deinit<Box<.t: t>> (
    .deinit = (.self: $&Box<.t: t>) -> () {
        record_drop(.amount = 1)
        nested ::= Other(.value = 0)
        deinit(.self = $&nested)
    }
)

implement Deinit<Other> (
    .deinit = (.self: $&Other) -> () {
        record_drop(.amount = 10)
    }
)

exercise := <.AllocatorType: Type: Allocator<AllocatorType>> (.allocator: $&AllocatorType) -> () {
    assume allocator
    first ::= Box<.t: Int32>(.value = 4)
    second ::= Box<.t: UnicodeScalar>(.value = 'a')
    other ::= Other(.value = 9)
    explicit ::= Other(.value = 3)
    deinit(.self = $&explicit)
    array ::= unwrap_or_abort(.value = DynamicArray<.t: Box<.t: UnicodeScalar>>(.capacity = 1))
    element ::= Box<.t: UnicodeScalar>(.value = 'b')
    pushed ::= push(.self = $&array, .value = ~element)
    if is(.value = pushed, .variant = ..error) { abort }
}

main := (.system: System) -> (.status_code: Int32) {
    exercise(.allocator = system.page_allocator)
    if drops != 53 {
        status_code = 1
        return
    }
    status_code = 0
}
