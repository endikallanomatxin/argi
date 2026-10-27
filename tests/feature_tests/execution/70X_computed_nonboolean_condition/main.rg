number := () -> (.value: Int32 = 1) {}

main := () -> () { #if number() {} }
