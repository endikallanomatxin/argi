identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

identity := #(.T: Type, .Unused: Type) (.value: T) -> (.result: T) { result = value }

main := () -> () {}
