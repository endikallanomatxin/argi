Box := #(.T: Type) (.value: T)
accept := #(.F: Function) () -> () {}
main := () -> () { accept#(.F = Box)() }
