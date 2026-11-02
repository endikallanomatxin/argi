..copy_failed

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

require_array_reasons := #(
    .t : Type: FalliblyCopyable#(
        .Value    : t,
        .reasons  : (..copy_failed, ..out_of_memory)
    )
) (.value: &t) -> () {}

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    source ::= unwrap_or_abort(.value = DynamicArray#(.t: FallibleValue)(.capacity = 1))
    defer deinit(.self = $&source)
    value ::= FallibleValue(.value = 42)
    push_assume_capacity#(.t: FallibleValue)(.self = $&source, .value = ~value)

    require_array_reasons(.value = &source)

    nested ::= unwrap_or_abort(
        .value = DynamicArray#(.t: DynamicArray#(.t: FallibleValue))(.capacity = 1)
    )
    defer deinit(.self = $&nested)
    require_array_reasons(.value = &nested)
}
