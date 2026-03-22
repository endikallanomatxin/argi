-- Arrays constructed from list literals allocate storage and copy elements.
main () -> (.status_code: Int32) := {
    arr :: [3]Int32 = (10, 20, 30)
    ro : ListViewRO#(.list_type: [3]Int32, .list_value_type: Int32) = (
        .list = &arr,
        .start = 0,
        .length = 3,
    )
    rw : ListViewRW#(.list_type: [3]Int32, .list_value_type: Int32) = (
        .list = $&arr,
        .start = 0,
        .length = 3,
    )
    ro_copy : ListViewRO#(.list_type: [3]Int32, .list_value_type: Int32) = ro

    if ro.length != 3 {
        status_code = 1
        return
    }

    if rw.length != 3 {
        status_code = 2
        return
    }

    if ro_copy.start != 0 {
        status_code = 3
        return
    }

    arr[1] = 99

    ro_snapshot : ListViewRO#(.list_type: [3]Int32, .list_value_type: Int32) = ro
    arr_snapshot :: [3]Int32 = ro_snapshot.list&

    if arr_snapshot[1] != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
