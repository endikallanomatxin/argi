-- Arrays constructed from list literals allocate storage and copy elements.
main () -> (.status_code: Int32) := {
    arr :: [3]Int32 = (10, 20, 30)
     -- arr is now an array of three Int32 values: 10, 20, and 30.

     from : Int32 = 0
     to: Int32 = 2

     v ::= view(.list=arr, .from=from, .to=to)
     -- Is equivalent to:
     -- v :: ListView#(
     --     .list_type=type_of(.value=arr),
     --     .list_value_type=Int32,
     -- ) = view#(.list_value_type=Int32)(.list=arr, .from=from, .to=to)

    -- if length(.value=view) != 3 {
    --     status_code = 1
    --     return
    -- }

    first :: Int32 = v[0]
    if first != 10 {
        status_code = 2
        return
    }

    second :: Int32 = v[1]
    if second != 20 {
        status_code = 3
        return
    }

    v[1] = 99
    updated :: Int32 = v[1]
    if updated != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
