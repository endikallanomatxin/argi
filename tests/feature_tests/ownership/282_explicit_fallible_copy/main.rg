FallibleValue : Type = (
    .value: Int32
)

copy(.self: &FallibleValue, .allocator: $&Allocator) -> (.result: Errable#(.t: FallibleValue, .reasons: (..copy_failed))) := {
    assume allocator

    result = ..ok (.value = self&.value)
}

FallibleValue implements FalliblyCopyable#(.reasons: (..copy_failed))

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    first :: FallibleValue = (.value = 21)
    copied ::= copy(.self = &first)
    match copied {
        ..error _ { status_code = 1 }
        ..ok ~ payload { status_code = first.value + payload.value - 42 }
    }
}
