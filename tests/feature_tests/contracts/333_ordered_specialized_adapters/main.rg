Box#(.T: Type): Type = (.value: T)

classifications :: Int32 = 0
generic_predicates :: Int32 = 0
concrete_predicates :: Int32 = 0

implement#(.T: Type: ImplicitlyCopyable) Compare#(&Box#(T), &Box#(T)) (
        .compare = (
                .left  : &Box#(T),
                .right : &Box#(T)
            ) -> (
                .order : Ordering
            ) {
            classifications = classifications + 1
            order = Compare#(T, T).compare(.left = left&.value, .right = right&.value).order
        }
    )

implement#(.T: Type: ImplicitlyCopyable) CompareRelations#(&Box#(T), &Box#(T)) (
        .less_than = (
                .left  : &Box#(T),
                .right : &Box#(T)
            ) -> (
                .ok : Bool
            ) {
            generic_predicates = generic_predicates + 1
            ok = left&.value < right&.value
        }
        .less_than_or_equal = (
                .left  : &Box#(T),
                .right : &Box#(T)
            ) -> (
                .ok : Bool
            ) {
            generic_predicates = generic_predicates + 1
            ok = left&.value <= right&.value
        }
        .greater_than = (
                .left  : &Box#(T),
                .right : &Box#(T)
            ) -> (
                .ok : Bool
            ) {
            generic_predicates = generic_predicates + 1
            ok = left&.value > right&.value
        }
        .greater_than_or_equal = (
                .left  : &Box#(T),
                .right : &Box#(T)
            ) -> (
                .ok : Bool
            ) {
            generic_predicates = generic_predicates + 1
            ok = left&.value >= right&.value
        }
    )

implement CompareRelations#(&Box#(Int32), &Box#(Int32)) (
    .less_than = (.left: &Box#(Int32), .right: &Box#(Int32)) -> (.ok: Bool) {
        concrete_predicates = concrete_predicates + 1
        ok = left&.value < right&.value
    }
    .less_than_or_equal = (.left: &Box#(Int32), .right: &Box#(Int32)) -> (.ok: Bool) {
        concrete_predicates = concrete_predicates + 1
        ok = left&.value <= right&.value
    }
    .greater_than = (.left: &Box#(Int32), .right: &Box#(Int32)) -> (.ok: Bool) {
        concrete_predicates = concrete_predicates + 1
        ok = left&.value > right&.value
    }
    .greater_than_or_equal = (.left: &Box#(Int32), .right: &Box#(Int32)) -> (.ok: Bool) {
        concrete_predicates = concrete_predicates + 1
        ok = left&.value >= right&.value
    }
)

ordered#(.T: Type)(.a: &T, .b: &T) -> (.ok: Bool) := {
    ok = a < b and a <= b and b > a and b >= a
}

main := () -> (.status_code: Int32 = 0) {
    a: Box#(UInt8) = (.value = 2)
    b: Box#(UInt8) = (.value = 5)
    c: Box#(Int32) = (.value = 2)
    d: Box#(Int32) = (.value = 5)
    if ordered(&a, &b).ok == false or ordered(&c, &d).ok == false { status_code = 1 }
    if classifications != 0 or generic_predicates != 4 or concrete_predicates != 4 {
        status_code = 2
    }
}
