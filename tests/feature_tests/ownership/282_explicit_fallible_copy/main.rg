FallibleValue := (
    .value : Int32
)

implement FalliblyCopyable#(FallibleValue) (
    .reasons : Type = (..copy_failed)
    .copy    = (.self: &FallibleValue, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(.t: FallibleValue, .reasons: (..copy_failed))
    ) {

        assume allocator

        result = ..ok(.value = self&.value)
    }

)

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    first :: FallibleValue = (.value = 21)
    copied ::= FalliblyCopyable#(
        FallibleValue
    ).copy(.self = &first, .allocator = allocator)
    match copied {
        ..error _ { status_code = 1 }
        ..ok ~payload { status_code = first.value + payload.value - 42 }
    }
}
