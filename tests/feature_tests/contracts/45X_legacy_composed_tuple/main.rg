Pair <.Left: Type, .Right: Type >: Contract = ()
Wrapper <.Value: Type >: Contract = (Pair < Value, Int32 >)
Cell: Type = ()
implement Wrapper < Cell > ()
main := () -> () {}
