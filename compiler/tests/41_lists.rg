main () -> (.status_code: Int32) := {
    data :: Int32 = 42
    a : Array#(.t=Int32) = (.data= $&data, .length=1)
    o := a[0]
    if o != 42 {
        status_code = 1
    }
}
