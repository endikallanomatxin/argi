Backend : Abstract = (
    perform(.self: &Self) -> (.value: Int32)
)

BackendA : Type = (.value: Int32)
BackendB : Type = (.value: Int32, .extra: Int32)

perform(.self: &BackendA) -> (.value: Int32) := {
    value = self&.value + 10
}

perform(.self: &BackendB) -> (.value: Int32) := {
    value = self&.value + self&.extra + 20
}

BackendA implements Backend
BackendB implements Backend

Wrapper #(.backend_type: Type: Backend) : Type = (
    .backend: $&backend_type
)

InlineHolder #(.backend_type: Type: Backend) : Type = (
    .backend: backend_type
)

Outer #(.t: Type) : Type = (
    .value: t
)

call#(.backend_type: Type: Backend)(
    .wrapper: &Wrapper#(.backend_type: backend_type)
) -> (.value: Int32) := {
    value = perform(.self = wrapper&.backend).value
}

main() -> (.status_code: Int32) := {
    a :: BackendA = (.value = 1)
    b :: BackendB = (.value = 2, .extra = 3)
    a_wrapper : Wrapper#(.backend_type: BackendA) = (.backend = $&a)
    b_wrapper : Wrapper#(.backend_type: BackendB) = (.backend = $&b)
    nested : Outer#(.t: Wrapper#(.backend_type: BackendA)) = (.value = a_wrapper)
    inline_a : InlineHolder#(.backend_type: BackendA) = (.backend = a)
    inline_b : InlineHolder#(.backend_type: BackendB) = (.backend = b)

    if call(.wrapper = &a_wrapper).value != 11 {
        status_code = 1
        return
    }
    if call(.wrapper = &b_wrapper).value != 25 {
        status_code = 2
        return
    }
    if nested.value.backend&.value != 1 {
        status_code = 3
        return
    }
    if size_of(.type = type_of(.value = inline_a)) >= size_of(.type = type_of(.value = inline_b)) {
        status_code = 4
        return
    }
    if inline_a.backend.value + inline_b.backend.extra != 4 {
        status_code = 5
        return
    }
    status_code = 0
}
