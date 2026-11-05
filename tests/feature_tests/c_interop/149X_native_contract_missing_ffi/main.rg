native_abs(.value: Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_abs") where { no_access() }
main := () -> () { _ = native_abs(.value = -1) }
