Mode: Type = (..quiet, ..verbose)

Options#(.T: Type): Type = (.value: T, .mode: Mode, .enabled: Bool, .marker: UnicodeScalar)

implement#(.T: Type) Init#(
    Options#(T),
    (
        .value: T, .mode: Mode = ..quiet, .enabled: Bool = true, .marker: UnicodeScalar = 'Q'
    )
) (
    .Result : Type = Options#(T)
    .init   = (
        .args : (
            .value   : T
            .mode    : Mode = ..quiet
            .enabled : Bool = true
            .marker  : UnicodeScalar = 'Q'
        )
    ) -> (.result: Result) {
        result = (
            .value   = args.value
            .mode    = args.mode
            .enabled = args.enabled
            .marker  = args.marker
        )
    }
)

main := () -> (.status_code: Int32 = 0) {
    defaults ::= Options#(Int32)(.value = 42)
    if defaults.value != 42 or defaults.enabled == false or defaults.marker != 'Q' { abort }
    if is(.value = defaults.mode, .variant = ..quiet) {} else { abort }
    explicit ::= Options#(Int32)(.value = 7, .mode = ..verbose, .enabled = false, .marker = 'V')
    if explicit.value != 7 or explicit.enabled or explicit.marker != 'V' { abort }
    if is(.value = explicit.mode, .variant = ..verbose) {} else { abort }
}
