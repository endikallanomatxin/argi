less#(.T: Type)(.a: T, .b: T) -> (.ok: Bool) := { ok = a < b }

main := () -> (.status_code: Int32 = 0) {
    narrow: UInt8 = 7
    if narrow < 7 or narrow > 7 or [narrow <= 7] == false or [narrow >= 7] == false {
        status_code = 1
    }
    if less(narrow, 8).ok == false { status_code = 2 }
    zero: Float32 = 0.0
    nan: Float32 = zero / zero
    if nan < zero or nan <= zero or nan > zero or nan >= zero { status_code = 3 }
    if zero < nan or zero <= nan or zero > nan or zero >= nan { status_code = 4 }
    if less(nan, zero).ok or nan == nan or [nan != nan] == false { status_code = 5 }
    if CompareRelations#(Float32, Float32).less_than_or_equal(.left = nan, .right = zero).ok {
        status_code = 6
    }
    if Compare#(Float32, Float32).compare(.left = nan, .right = zero).order != ..unordered {
        status_code = 7
    }
    if [
        is_less_than(..unordered).ok
        or is_less_than_or_equal(..unordered).ok
        or is_greater_than(..unordered).ok
        or is_greater_than_or_equal(..unordered).ok
    ] { status_code = 8 }
    requires_total(narrow)

}

requires_total#(.T: Type: TotalOrder#(T, T)) := (.value: T) -> () {}
