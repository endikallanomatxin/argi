dep := import("./dep")
read := #(.T: Type) (.value: T) -> (.result: Int32) { result = value._hidden }
main := () -> () { _ = read(.value = dep.make()) }
