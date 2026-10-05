main() -> (
        .result : Errable#(.t: Void, .reasons: (..invalid_option, ..missing_option_value)) = ..ok Void()
    ) := {
    args :: [7]StringView = ("-ab", "--size=12", "--offset", "-3", "file", "--", "--literal")
    source ::= CliArgumentViews(.values = view(.array = &args))
    parser ::= CliParser#(.t: CliArgumentViews)(.source = &source)
    index :: Int32 = 0
    while true {
        match next(.self = $&parser)! {
            ..none { break }
            ..some item {
                match item.value {
                    ..option option {
                        if index == 0 and option.name != "a" { abort }
                        if index == 1 and option.name != "b" { abort }
                        if index == 2 {
                            if take_value(.self = $&parser, .option = option)! != "12" { abort }
                        }
                        if index == 3 {
                            if take_value(.self = $&parser, .option = option)! != "-3" { abort }
                        }
                    }
                    ..positional text {
                        if index == 4 and text != "file" { abort }
                        if index == 5 and text != "--literal" { abort }
                    }
                }
                index = index + 1
            }
        }
    }
    if index != 6 { abort }
    bad :: [1]StringView = ("--=bad")
    bad_view ::= CliArgumentViews(.values = view(.array = &bad))
    invalid ::= CliParser#(.t: CliArgumentViews)(.source = &bad_view)
    match next(.self = $&invalid) {
        ..ok _ { abort } ..error&err { if [
                err&.reason
                != ..invalid_option
            ] { abort } }
    }
}
