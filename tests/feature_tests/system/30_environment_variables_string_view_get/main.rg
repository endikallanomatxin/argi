main := (.system: System) -> (.status_code: Int32) {

    assume ffi := system.ffi
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    key ::= "PATH"

    found_result ::= lookup_environment(.self = system.env_vars, .key = key)
    if is(.value = found_result, .variant = ..error) {
        status_code = 3
        return
    }
    found ::= found_result ..ok
    if found ?{
    } else {
        status_code = 1
        return
    }

    payload ::= found ..some
    if byte_length(&payload.value).count == 0 {
        status_code = 2
        return
    }

    status_code = 0
}
