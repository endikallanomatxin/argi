identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
int_identity := identity#(Int32)
Fixed#(.T: Type): Contract = (.fixed_value: (.value: T) -> (.result: T))
implement Fixed#(Bool) (.fixed_value = int_identity)
main := () -> () {}
