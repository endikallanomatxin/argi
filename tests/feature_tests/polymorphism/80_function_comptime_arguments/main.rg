dep := import("./dep")
one := () -> (.result: Bool) { result = true }
two := () -> (.result: Bool) { result = false }
identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
fixed := identity#(Int32)
alias := one

call := #(.F: Function = one) () -> (.result: Bool) {
    result = F().result
}
forward := #(.F: Function) () -> (.result: Bool) {
    result = call#(.F = F)().result
}

apply := #(.F: Function) (.value: Int32) -> (.result: Int32) { result = F(.value = value).result }

main := () -> () {
    value: result_of#(fixed) = 7
    if value != 7 { abort }
    if forward#(.F = dep.truth)().result {} else { abort }
    if forward#(.F = alias)().result {} else { abort }
    if apply#(.F = fixed)(.value = 7).result == 7 {} else { abort }
    if call().result {} else { abort }
    if forward#(.F = one)().result {} else { abort }
    if forward#(.F = two)().result { abort }
}
