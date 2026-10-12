Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
first#(.n: Int)(.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) := { value = values&[0] }
