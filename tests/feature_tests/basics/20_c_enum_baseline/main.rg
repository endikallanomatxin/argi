AccessMode : CEnum = (
    ..missing,
    ..exists,
)

choose(.flag: Bool) -> (.mode: AccessMode) := {
    if flag {
        mode = ..exists
        return
    }

    mode = ..missing
}

main() -> (.status_code: Int32) := {
    mode : AccessMode = ..exists
    if mode != ..exists {
        status_code = 1
        return
    }

    chosen ::= choose(.flag = 0 == 1)
    if chosen != ..missing {
        status_code = 2
        return
    }

    enum_size :: UIntNative = size_of(.type = AccessMode)
    if enum_size != 4 {
        status_code = 3
        return
    }

    enum_alignment :: UIntNative = alignment_of(.type = AccessMode)
    if enum_alignment != 4 {
        status_code = 4
        return
    }

    status_code = 0
}
