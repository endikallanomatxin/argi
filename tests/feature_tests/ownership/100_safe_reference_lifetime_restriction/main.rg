Pair : Type = (
    .lifetime: Allocation
    .marker: Int32
)

ReferenceChoice : Type = (
    ..some &UInt8
    ..none
)

restrict_twice#(.t: Type)(.input: t, .first: &Any, .second: &Any) -> (.reference: t) := {
    intermediate ::= restrict_reference#(.t: t)(.input = input, .lifetime = first).reference
    reference = restrict_reference#(.t: t)(.input = intermediate, .lifetime = second).reference
}

main(.system: System = System()) -> (.status_code: Int32) := {
    source_result ::= allocate(.self = system.allocator, .size = 1)
    first_result ::= allocate(.self = system.allocator, .size = 1)
    second_result ::= allocate(.self = system.allocator, .size = 1)
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    match second_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ second_payload {
                            source ::= ~source_payload
                            pair :: Pair = (.lifetime = ~first_payload, .marker = 7)
                            second ::= ~second_payload
                            original ::= source.data
                            readonly ::= read_reference(.base = original).reference
                            restricted ::= restrict_reference#(.t: $&UInt8)(.input = original, .lifetime = &pair.lifetime).reference
                            readonly_restricted ::= restrict_reference#(.t: &UInt8)(.input = readonly, .lifetime = &pair.marker).reference
                            chained ::= restrict_twice(.input = restricted, .first = &pair.marker, .second = &second).reference
                            relocated :: &UInt8 = chained
                            relocated = read_reference(.base = restricted).reference
                            choice :: ReferenceChoice = ..some readonly_restricted
                            match choice {
                                ..none { status_code = 4 }
                                ..some chosen {
                                    if chosen& != 0 or relocated& != 0 or original& != 0 {
                                        status_code = 5
                                    } else {
                                        deinit(.self = $&second)
                                        deinit(.self = $&pair.lifetime)
                                        if original& == 0 {
                                            status_code = 0
                                        } else {
                                            status_code = 6
                                        }
                                    }
                                }
                            }
                            deinit(.self = $&source)
                        }
                    }
                }
            }
        }
    }
}
