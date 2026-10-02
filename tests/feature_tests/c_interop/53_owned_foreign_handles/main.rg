owned := import("../../_support/owned_foreign_handle")
..operation_failed

_return_early(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.value: CInt) := {
    assume ffi := ffi
    handle ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 17))
    value = owned.read(.self = &handle)
    return
}

_fail() -> (.result: Errable#(.t: Void, .reasons: (..operation_failed))) := {
    result = ..error(.reason = ..operation_failed)
}

_propagate_failure(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Errable#(.t: Void, .reasons: (..operation_failed))) := {
    assume ffi := ffi
    handle ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 23))
    _fail()!
    result = ..ok Void()
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    {
        first ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 42))
        if owned.live() != 1 or owned.read(.self = &first) != 42 {
            status_code = 1
            return
        }
        moved ::= ~first
        if owned.read(.self = &moved) != 42 {
            status_code = 2
            return
        }
    }
    if owned.live() != 0 or owned.created() != 1 or owned.destroyed() != 1 {
        status_code = 3
        return
    }
    if _return_early() != 17 or owned.live() != 0 {
        status_code = 4
        return
    }
    failure := owned.OwnedHandle(.value = 0, .fail = true)
    if is(.value = failure, .variant = ..ok) {
        status_code = 5
        return
    }
    if owned.created() != 2 or owned.destroyed() != 2 {
        status_code = 6
        return
    }
    propagated := _propagate_failure()
    if is(.value = propagated, .variant = ..ok) or owned.live() != 0 {
        status_code = 7
        return
    }
    {
        explicit :: owned.GenericHandle#(.t: Int32) = unwrap_or_abort(.value = owned.GenericHandle(.tag = 41))
        inferred ::= unwrap_or_abort(.value = owned.GenericHandle(.tag = 42))
        if explicit.tag != 41 or inferred.tag != 42 or owned.live() != 2 {
            status_code = 9
            return
        }
    }
    if owned.live() != 0 or owned.created() != 5 or owned.destroyed() != 5 or owned.violations() != 0 {
        status_code = 8
        return
    }
}
