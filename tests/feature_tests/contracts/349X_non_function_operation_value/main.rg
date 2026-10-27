number := 42
Action#(.T: Type): Contract = (.act: _)
implement Action#(Int32) (.act = number)
main := () -> () {}
