Buffer : Type = (
    .data: $&UInt8
)

release(.self: $&Buffer) -> () := {
    end_root#(.t: UInt8)(.resource = ~self&.data)
}

main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    raw ::= raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte))
    data ::= establish_fresh_reference#(.t: UInt8)(.raw = raw)
    alias ::= data
    buffer :: Buffer = (.data = ~data)

    release(.self = $&buffer)
    if alias& == 7 {
        status_code = 0
    }
}
