B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    byte_a :: UInt8 = 3
    ref_a ::= establish_fresh_reference#(.t: UInt8)(.raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte_a)))
    b :: B = (.value = 5, .to_a = ref_a)

    end_root#(.t: UInt8)(.resource = ~ref_a)
    if b.to_a& == 3 {
        status_code = 0
    }
}
