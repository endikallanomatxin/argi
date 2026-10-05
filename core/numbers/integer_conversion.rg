-- Bounds are expressed in the source domain, so the check precedes any
-- truncation or signedness change. Semantizing supplies their intersection.
_checked_integer_conversion#(
        .from : Type,
        .to   : Type
    )(
        .value   : from,
        .minimum : from,
        .maximum : from,
    ) -> (
        .result : Errable#(.t: to, .reasons: (..out_of_range))
    ) := {
    if value < minimum or value > maximum {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok __integer_conversion#(.to: to)(.value = value)
}
