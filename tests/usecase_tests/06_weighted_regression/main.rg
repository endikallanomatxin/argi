math ::= import ("math/linear_algebra")

-- Form the normal equations for y = intercept + slope * x. The diagonal
-- weights stay compact while their products with the design matrix are dense.
main() -> (.status_code: Int32 = 0) := {
    design: math.Matrix#(.rows = 3, .cols = 2, .t: Float64) = (
        .values = (
            (1.0, 0.0),
            (1.0, 1.0),
            (1.0, 2.0)
        )
    )
    observations: math.Matrix#(.rows = 3, .cols = 1, .t: Float64) = (
        .values = (
            (1.0),
            (3.0),
            (5.0)
        )
    )
    weights ::= math.Diagonal#(.n = 3, .t: Float64)(.values = (1.0, 2.0, 1.0))
    weighted_design ::= &weights * &design
    weighted_observations ::= &weights * &observations
    transposed ::= math.MatrixTransposition#(
        math.Matrix#(.rows = 3, .cols = 2, .t: Float64)
    ).transpose(&design)
    normal ::= &transposed * &weighted_design
    rhs ::= &transposed * &weighted_observations
    determinant ::= [
        normal.values[0][0] * normal.values[1][1]
        - normal.values[0][1] * normal.values[1][0]
    ]
    intercept ::= [
        [rhs.values[0][0] * normal.values[1][1] - normal.values[0][1] * rhs.values[1][0]]
        / determinant
    ]
    slope ::= [
        [normal.values[0][0] * rhs.values[1][0] - rhs.values[0][0] * normal.values[1][0]]
        / determinant
    ]
    if [intercept >= 0.999999 and intercept <= 1.000001] == false { status_code = 1 }
    if [slope >= 1.999999 and slope <= 2.000001] == false { status_code = 2 }
}
