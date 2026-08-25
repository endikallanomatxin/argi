A : Type = (.value: UInt8, .to_b: $&UInt8)
B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    byte_a :: UInt8 = 3
    byte_b :: UInt8 = 5
    ref_a ::= establish_fresh_reference#(.t: UInt8)(.raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte_a)))
    ref_b ::= establish_fresh_reference#(.t: UInt8)(.raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte_b)))
    a :: A = (.value = 3, .to_b = ref_b)
    b :: B = (.value = 5, .to_a = ref_a)

    end_root#(.t: UInt8)(.resource = ~ref_a)
    status_code = 0
    if b.value != 5 {
        status_code = 1
    }
    if a.to_b& != 5 {
        status_code = 2
    }
    end_root#(.t: UInt8)(.resource = ~ref_b)
}
