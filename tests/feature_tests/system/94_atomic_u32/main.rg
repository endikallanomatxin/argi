main(.system: System) -> !Void = ..ok Void() := {
    cell ::= AtomicUInt32(.initial = 7, .ffi = system.ffi)!
    if load(.self = &cell).value != 7 { abort }
    if exchange(.self = $&cell, .value = 10).previous != 7 { abort }
    if fetch_add(.self = $&cell, .value = 3).previous != 10 { abort }
    failed ::= compare_exchange(.self = $&cell, .expected = 10, .desired = 20)
    if failed.swapped or failed.observed != 13 { abort }
    succeeded ::= compare_exchange(.self = $&cell, .expected = 13, .desired = 20)
    if succeeded.swapped == false or succeeded.observed != 13 { abort }
    store(.self = $&cell, .value = 4294967295)
    if fetch_add(.self = $&cell, .value = 1).previous != 4294967295 { abort }
    if load(.self = &cell).value != 0 { abort }
}
