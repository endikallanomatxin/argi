FallibleValue := (
    .value : Int32
)

implement#(.Provider: Type: Allocator) FalliblyCopyable#(FallibleValue, Provider) (
    .reasons : Type = (..copy_failed)
    .copy    = (.self: &FallibleValue, .allocator: $&Provider) -> (
        .result : Errable#(.t: FallibleValue, .reasons: (..copy_failed))
    ) {

        assume allocator

        result = ..ok(.value = self&.value)
    }

)

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    first :: FallibleValue = (.value = 21)
    copied ::= FalliblyCopyable#(
        FallibleValue, GeneralPurposeAllocator
    ).copy(.self = &first, .allocator = allocator)
    match copied {
        ..error _ { status_code = 1 }
        ..ok ~payload { status_code = first.value + payload.value - 42 }
    }
}
