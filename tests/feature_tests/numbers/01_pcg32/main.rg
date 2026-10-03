-- Known sequences are generated with an independent exact-integer model of
-- PCG's 64-bit recurrence and XSH-RR output permutation.
expect_word(.self: $&Pcg32, .expected: UInt32) -> () := {
    if next_uint32(.self = self).value != expected { abort }
}
expect_float16(.actual: Float16, .expected: Float16) -> () := {
    if actual != expected { abort }
}
expect_float32(.actual: Float32, .expected: Float32) -> () := {
    if actual != expected { abort }
}
expect_float64(.actual: Float64, .expected: Float64) -> () := {
    if actual != expected { abort }
}
main() -> (.status_code: Int32 = 0) := {
    generator ::= Pcg32(.seed = 0)
    reseed(.self = $&generator, .seed = 0)
    expect_word(.self = $&generator, .expected = 3894649422)
    expect_word(.self = $&generator, .expected = 2055130073)
    expect_word(.self = $&generator, .expected = 2315086854)
    expect_word(.self = $&generator, .expected = 2925816488)
    expect_word(.self = $&generator, .expected = 3443325253)
    expect_word(.self = $&generator, .expected = 1644475139)
    expect_word(.self = $&generator, .expected = 428639621)
    expect_word(.self = $&generator, .expected = 1241310737)
    expect_word(.self = $&generator, .expected = 3521718650)
    expect_word(.self = $&generator, .expected = 338531392)
    expect_word(.self = $&generator, .expected = 4000707947)
    expect_word(.self = $&generator, .expected = 1195020567)
    expect_word(.self = $&generator, .expected = 3819198723)
    expect_word(.self = $&generator, .expected = 3169322913)
    expect_word(.self = $&generator, .expected = 3847118669)
    expect_word(.self = $&generator, .expected = 1232956497)
    expect_word(.self = $&generator, .expected = 1635946854)
    expect_word(.self = $&generator, .expected = 2806007627)
    expect_word(.self = $&generator, .expected = 51974824)
    expect_word(.self = $&generator, .expected = 2648956666)
    reseed(.self = $&generator, .seed = 1)
    expect_word(.self = $&generator, .expected = 1412771199)
    expect_word(.self = $&generator, .expected = 1791099446)
    expect_word(.self = $&generator, .expected = 124312908)
    expect_word(.self = $&generator, .expected = 1968572995)
    expect_word(.self = $&generator, .expected = 1080415314)
    expect_word(.self = $&generator, .expected = 2578637408)
    expect_word(.self = $&generator, .expected = 2103691749)
    expect_word(.self = $&generator, .expected = 1218125110)
    expect_word(.self = $&generator, .expected = 776621019)
    expect_word(.self = $&generator, .expected = 4155847760)
    expect_word(.self = $&generator, .expected = 458002924)
    expect_word(.self = $&generator, .expected = 2919723538)
    expect_word(.self = $&generator, .expected = 2795576424)
    expect_word(.self = $&generator, .expected = 3288055970)
    expect_word(.self = $&generator, .expected = 282060643)
    expect_word(.self = $&generator, .expected = 3322340095)
    expect_word(.self = $&generator, .expected = 2744574565)
    expect_word(.self = $&generator, .expected = 646512119)
    expect_word(.self = $&generator, .expected = 3118873679)
    expect_word(.self = $&generator, .expected = 3200416693)
    reseed(.self = $&generator, .seed = 42)
    expect_word(.self = $&generator, .expected = 3270867926)
    expect_word(.self = $&generator, .expected = 1795671209)
    expect_word(.self = $&generator, .expected = 1924641435)
    expect_word(.self = $&generator, .expected = 1143034755)
    expect_word(.self = $&generator, .expected = 4121910957)
    expect_word(.self = $&generator, .expected = 1757328946)
    expect_word(.self = $&generator, .expected = 3418829100)
    expect_word(.self = $&generator, .expected = 3589261271)
    expect_word(.self = $&generator, .expected = 2062288904)
    expect_word(.self = $&generator, .expected = 4279450293)
    expect_word(.self = $&generator, .expected = 3045727705)
    expect_word(.self = $&generator, .expected = 1731076225)
    expect_word(.self = $&generator, .expected = 106581468)
    expect_word(.self = $&generator, .expected = 4174699414)
    expect_word(.self = $&generator, .expected = 3841390673)
    expect_word(.self = $&generator, .expected = 251273835)
    expect_word(.self = $&generator, .expected = 3019696858)
    expect_word(.self = $&generator, .expected = 736288324)
    expect_word(.self = $&generator, .expected = 449296931)
    expect_word(.self = $&generator, .expected = 3244538308)
    reseed(.self = $&generator, .seed = 9223372036854775808)
    expect_word(.self = $&generator, .expected = 575596579)
    expect_word(.self = $&generator, .expected = 3420060286)
    expect_word(.self = $&generator, .expected = 1816562173)
    expect_word(.self = $&generator, .expected = 1793633892)
    expect_word(.self = $&generator, .expected = 4182232380)
    expect_word(.self = $&generator, .expected = 3003343365)
    expect_word(.self = $&generator, .expected = 2231703948)
    expect_word(.self = $&generator, .expected = 3860417020)
    expect_word(.self = $&generator, .expected = 694866409)
    expect_word(.self = $&generator, .expected = 2487243821)
    expect_word(.self = $&generator, .expected = 4125879925)
    expect_word(.self = $&generator, .expected = 2434221880)
    expect_word(.self = $&generator, .expected = 3640910756)
    expect_word(.self = $&generator, .expected = 128040136)
    expect_word(.self = $&generator, .expected = 1330505038)
    expect_word(.self = $&generator, .expected = 1817528701)
    expect_word(.self = $&generator, .expected = 2439405962)
    expect_word(.self = $&generator, .expected = 1464575808)
    expect_word(.self = $&generator, .expected = 310903577)
    expect_word(.self = $&generator, .expected = 3740974563)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    expect_word(.self = $&generator, .expected = 3643879478)
    expect_word(.self = $&generator, .expected = 3444271506)
    expect_word(.self = $&generator, .expected = 2072954526)
    expect_word(.self = $&generator, .expected = 2577256464)
    expect_word(.self = $&generator, .expected = 1548663211)
    expect_word(.self = $&generator, .expected = 3076993113)
    expect_word(.self = $&generator, .expected = 651909779)
    expect_word(.self = $&generator, .expected = 1443070399)
    expect_word(.self = $&generator, .expected = 3080190163)
    expect_word(.self = $&generator, .expected = 1280840547)
    expect_word(.self = $&generator, .expected = 1466252)
    expect_word(.self = $&generator, .expected = 2473328129)
    expect_word(.self = $&generator, .expected = 2251486370)
    expect_word(.self = $&generator, .expected = 3363763389)
    expect_word(.self = $&generator, .expected = 4168170007)
    expect_word(.self = $&generator, .expected = 35691479)
    expect_word(.self = $&generator, .expected = 3251864675)
    expect_word(.self = $&generator, .expected = 836802106)
    expect_word(.self = $&generator, .expected = 97221590)
    expect_word(.self = $&generator, .expected = 221935416)
    reseed(.self = $&generator, .seed = 9624256412291681990)
    expect_word(.self = $&generator, .expected = 0)
    expect_word(.self = $&generator, .expected = 1613493245)
    expect_word(.self = $&generator, .expected = 3894649422)
    expect_word(.self = $&generator, .expected = 2055130073)
    expect_word(.self = $&generator, .expected = 2315086854)
    expect_word(.self = $&generator, .expected = 2925816488)
    expect_word(.self = $&generator, .expected = 3443325253)
    expect_word(.self = $&generator, .expected = 1644475139)
    expect_word(.self = $&generator, .expected = 428639621)
    expect_word(.self = $&generator, .expected = 1241310737)
    expect_word(.self = $&generator, .expected = 3521718650)
    expect_word(.self = $&generator, .expected = 338531392)
    expect_word(.self = $&generator, .expected = 4000707947)
    expect_word(.self = $&generator, .expected = 1195020567)
    expect_word(.self = $&generator, .expected = 3819198723)
    expect_word(.self = $&generator, .expected = 3169322913)
    expect_word(.self = $&generator, .expected = 3847118669)
    expect_word(.self = $&generator, .expected = 1232956497)
    expect_word(.self = $&generator, .expected = 1635946854)
    expect_word(.self = $&generator, .expected = 2806007627)
    reseed(.self = $&generator, .seed = 8160223694559104710)
    expect_word(.self = $&generator, .expected = 4294967295)
    expect_word(.self = $&generator, .expected = 4190648745)
    expect_word(.self = $&generator, .expected = 1482006935)
    expect_word(.self = $&generator, .expected = 690750146)
    expect_word(.self = $&generator, .expected = 329230960)
    expect_word(.self = $&generator, .expected = 3218711595)
    expect_word(.self = $&generator, .expected = 2890187390)
    expect_word(.self = $&generator, .expected = 2496807331)
    expect_word(.self = $&generator, .expected = 1310412769)
    expect_word(.self = $&generator, .expected = 3119656358)
    expect_word(.self = $&generator, .expected = 183966898)
    expect_word(.self = $&generator, .expected = 3643125721)
    expect_word(.self = $&generator, .expected = 3381376241)
    expect_word(.self = $&generator, .expected = 6615042)
    expect_word(.self = $&generator, .expected = 1210439137)
    expect_word(.self = $&generator, .expected = 1674587410)
    expect_word(.self = $&generator, .expected = 782083074)
    expect_word(.self = $&generator, .expected = 2828644367)
    expect_word(.self = $&generator, .expected = 2471153587)
    expect_word(.self = $&generator, .expected = 68328116)
    -- Copying snapshots the current state; instances advance independently.
    twin ::= generator
    duplicate ::= copy(.self = &generator).value
    count :: UInt32 = 0
    while count < 256 {
        expected ::= next_uint32(.self = $&generator).value
        expect_word(.self = $&twin, .expected = expected)
        expect_word(.self = $&duplicate, .expected = expected)
        count = count + 1
    }
    reseed(.self = $&generator, .seed = 0)
    if next_uint64(.self = $&generator).value != 16727391898930432985 { abort }
    if next_uint64(.self = $&generator).value != 9943222328255343272 { abort }
    if next_uint64(.self = $&generator).value != 14788969352770401027 { abort }
    if next_uint64(.self = $&generator).value != 1840993155206145553 { abort }
    expect_word(.self = $&generator, .expected = 3521718650)
    reseed(.self = $&generator, .seed = 42)
    if next_uint64(.self = $&generator).value != 14048270773501019305 { abort }
    if next_uint64(.self = $&generator).value != 8266272020994544515 { abort }
    if next_uint64(.self = $&generator).value != 17703472759096391218 { abort }
    if next_uint64(.self = $&generator).value != 14683759178702374871 { abort }
    expect_word(.self = $&generator, .expected = 2062288904)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    if next_uint64(.self = $&generator).value != 15650343192019822994 { abort }
    if next_uint64(.self = $&generator).value != 8903271897842438160 { abort }
    if next_uint64(.self = $&generator).value != 6651457846840340569 { abort }
    if next_uint64(.self = $&generator).value != 2799931182190657983 { abort }
    expect_word(.self = $&generator, .expected = 3080190163)
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 3)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 10)).result != 2 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2147483649)).result != 1747165773 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 4294967295)).result != 3894649422 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 3)).result != 2 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 10)).result != 6 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2147483649)).result != 1123384277 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 4294967295)).result != 3270867926 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1795671209) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1613493245) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1613493245) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 3)).result != 2 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 2 attempts
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 10)).result != 5 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 2 attempts
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 2147483649)).result != 1747165773 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2055130073) -- 3 attempts
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 4294967295)).result != 1613493245 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 2 attempts
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 2)).result != 1 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 3)).result != 2 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 10)).result != 5 {
        abort
    }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 9223372036854775809)).result != 7504019862075657176 { abort }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 0)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 18446744073709551615)).result != 16727391898930432985 { abort }
    expect_word(.self = $&generator, .expected = 2315086854) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 2)).result != 1 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 3)).result != 1 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 10)).result != 5 {
        abort
    }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 9223372036854775809)).result != 4824898736646243496 { abort }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 42)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 18446744073709551615)).result != 14048270773501019305 { abort }
    expect_word(.self = $&generator, .expected = 1924641435) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 1)).result != 0 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 2)).result != 1 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 3)).result != 2 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 10)).result != 5 {
        abort
    }
    expect_word(.self = $&generator, .expected = 3894649422) -- 1 attempt
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 9223372036854775809)).result != 7504019862075657176 { abort }
    expect_word(.self = $&generator, .expected = 2315086854) -- 2 attempts
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if unwrap_or_abort(.value = uniform_uint64(.self = $&generator,
            .upper_bound = 18446744073709551615)).result != 1613493245 { abort }
    expect_word(.self = $&generator, .expected = 3894649422) -- 1 attempt
    -- Invalid bounds report an error without consuming generator state.
    saved ::= generator
    invalid32 ::= uniform_uint32(.self = $&generator, .upper_bound = 0)
    if is(.value = invalid32, .variant = ..error) {
        if invalid32 ..error.reason != ..invalid_range { abort }
    } else { abort }
    invalid64 ::= uniform_uint64(.self = $&generator, .upper_bound = 0)
    if is(.value = invalid64, .variant = ..error) {
        if invalid64 ..error.reason != ..invalid_range { abort }
    } else { abort }
    expect_word(.self = $&generator, .expected = next_uint32(.self = $&saved).value)
    reseed(.self = $&generator, .seed = 0)
    if next_bool(.self = $&generator).value != true { abort }
    expect_word(.self = $&generator, .expected = 2055130073)
    reseed(.self = $&generator, .seed = 0)
    expect_float16(.actual = next_float16(.self = $&generator).value, .expected = 0.90673828125)
    expect_word(.self = $&generator, .expected = 2055130073)
    reseed(.self = $&generator, .seed = 0)
    expect_float32(.actual = next_float32(.self = $&generator).value,
        .expected = 0.90679371356964111328125)
    expect_word(.self = $&generator, .expected = 2055130073)
    reseed(.self = $&generator, .seed = 0)
    expect_float64(.actual = next_float64(.self = $&generator).value,
        .expected = 0.90679373184184008938046872572158463299274444580078125)
    expect_word(.self = $&generator, .expected = 2315086854)
    reseed(.self = $&generator, .seed = 42)
    if next_bool(.self = $&generator).value != true { abort }
    expect_word(.self = $&generator, .expected = 1795671209)
    reseed(.self = $&generator, .seed = 42)
    expect_float16(.actual = next_float16(.self = $&generator).value, .expected = 0.76123046875)
    expect_word(.self = $&generator, .expected = 1795671209)
    reseed(.self = $&generator, .seed = 42)
    expect_float32(.actual = next_float32(.self = $&generator).value,
        .expected = 0.761558234691619873046875)
    expect_word(.self = $&generator, .expected = 1795671209)
    reseed(.self = $&generator, .seed = 42)
    expect_float64(.actual = next_float64(.self = $&generator).value,
        .expected = 0.76155828461472108159568961127661168575286865234375)
    expect_word(.self = $&generator, .expected = 1924641435)
    reseed(.self = $&generator, .seed = 9624256412291681990)
    if next_bool(.self = $&generator).value != false { abort }
    expect_word(.self = $&generator, .expected = 1613493245)
    reseed(.self = $&generator, .seed = 9624256412291681990)
    expect_float16(.actual = next_float16(.self = $&generator).value, .expected = 0.0)
    expect_word(.self = $&generator, .expected = 1613493245)
    reseed(.self = $&generator, .seed = 9624256412291681990)
    expect_float32(.actual = next_float32(.self = $&generator).value, .expected = 0.0)
    expect_word(.self = $&generator, .expected = 1613493245)
    reseed(.self = $&generator, .seed = 9624256412291681990)
    expect_float64(.actual = next_float64(.self = $&generator).value,
        .expected = 0.0000000000874675887274634078494273126125335693359375)
    expect_word(.self = $&generator, .expected = 3894649422)
    reseed(.self = $&generator, .seed = 8160223694559104710)
    if next_bool(.self = $&generator).value != true { abort }
    expect_word(.self = $&generator, .expected = 4190648745)
    reseed(.self = $&generator, .seed = 8160223694559104710)
    expect_float16(.actual = next_float16(.self = $&generator).value, .expected = 0.99951171875)
    expect_word(.self = $&generator, .expected = 4190648745)
    reseed(.self = $&generator, .seed = 8160223694559104710)
    expect_float32(.actual = next_float32(.self = $&generator).value,
        .expected = 0.999999940395355224609375)
    expect_word(.self = $&generator, .expected = 4190648745)
    reseed(.self = $&generator, .seed = 8160223694559104710)
    expect_float64(.actual = next_float64(.self = $&generator).value,
        .expected = 0.99999999999434485697946684013004414737224578857421875)
    expect_word(.self = $&generator, .expected = 1482006935)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    if next_bool(.self = $&generator).value != true { abort }
    expect_word(.self = $&generator, .expected = 3444271506)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    expect_float16(.actual = next_float16(.self = $&generator).value, .expected = 0.84814453125)
    expect_word(.self = $&generator, .expected = 3444271506)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    expect_float32(.actual = next_float32(.self = $&generator).value,
        .expected = 0.84840679168701171875)
    expect_word(.self = $&generator, .expected = 3444271506)
    reseed(.self = $&generator, .seed = 18446744073709551615)
    expect_float64(.actual = next_float64(.self = $&generator).value,
        .expected = 0.84840680444658078673825229998328723013401031494140625)
    expect_word(.self = $&generator, .expected = 2072954526)
    zero16: Float16 = 0.0
    one16: Float16 = 1.0
    zero32: Float32 = 0.0
    one32: Float32 = 1.0
    zero64: Float64 = 0.0
    one64: Float64 = 1.0
    count = 0
    while count < 1024 {
        sample16 ::= next_float16(.self = $&generator).value
        sample32 ::= next_float32(.self = $&generator).value
        sample64 ::= next_float64(.self = $&generator).value
        if sample16 < zero16 or sample16 >= one16 { abort }
        if sample32 < zero32 or sample32 >= one32 { abort }
        if sample64 < zero64 or sample64 >= one64 { abort }
        if unwrap_or_abort(.value = uniform_uint32(.self = $&generator, .upper_bound = 37)).result >= 37 {
            abort
        }
        if unwrap_or_abort(.value = uniform_uint64(.self = $&generator, .upper_bound = 1000000000000)).result >= 1000000000000 {
            abort
        }
        count = count + 1
    }
}
