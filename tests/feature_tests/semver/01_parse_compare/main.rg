semver := import ("semver")
main() -> (.status_code: Int32 = 0) := {
    first ::= unwrap_or_abort(.value = semver.parse(.text = "1.2.3-alpha.2+001")).result
    second ::= unwrap_or_abort(.value = semver.VersionView(.text = "1.2.3-alpha.11+other")).result
    if semver.compare(.left = &first, .right = &second).order != -1 { abort }
    if semver.major(.self = &first).text != "1" { abort }
    if semver.minor(.self = &first).text != "2" { abort }
    if semver.patch(.self = &first).text != "3" { abort }
    if semver.pre_release(.self = &first).text != "alpha.2" { abort }
    if semver.build_metadata(.self = &first).text != "001" { abort }
    stable ::= unwrap_or_abort(.value = semver.parse(.text = "0.0.0")).result
    if semver.pre_release(.self = &stable).text.length != 0 { abort }
    if semver.build_metadata(.self = &stable).text.length != 0 { abort }
    copy ::= stable
    if semver.equals(.left = &stable, .right = &copy).ok == false { abort }
    nul_bytes: [7]UInt8 = (49, 46, 50, 46, 51, 0, 65)
    nul: StringView = (.data = &nul_bytes[0], .length = 7)
    check_invalid(.text = nul)
    check_valid(.text = "0.0.0")
    check_valid(.text = "1.2.3")
    check_valid(.text = "1.2.3-0")
    check_valid(.text = "1.2.3-00a")
    check_valid(.text = "1.2.3--")
    check_valid(.text = "1.2.3-alpha.0+001.foo")
    check_valid(.text = "1.2.3+00")
    check_valid(.text = "999999999999999999999999999.2.3")
    check_valid(.text = "1.2.3-9999999999999999999999999999999")
    check_invalid(.text = "")
    check_invalid(.text = "1")
    check_invalid(.text = "1.2")
    check_invalid(.text = "1.2.3.4")
    check_invalid(.text = "01.2.3")
    check_invalid(.text = "1.02.3")
    check_invalid(.text = "1.2.03")
    check_invalid(.text = "v1.2.3")
    check_invalid(.text = " 1.2.3")
    check_invalid(.text = "1.2.3 ")
    check_invalid(.text = "1.2.3-")
    check_invalid(.text = "1.2.3+")
    check_invalid(.text = "1.2.3-01")
    check_invalid(.text = "1.2.3-a..b")
    check_invalid(.text = "1.2.3+a..b")
    check_invalid(.text = "1.2.3-.a")
    check_invalid(.text = "1.2.3-a.")
    check_invalid(.text = "1.2.3-a_b")
    check_invalid(.text = "1.2.3+á")
    check_invalid(.text = "1.2.3+x+y")
    check_invalid(.text = "-1.2.3")
    check_invalid(.text = "1.2.3-00.1")
    check_order(.a = "1.0.0-alpha", .b = "1.0.0-alpha.1", .order = -1)
    check_order(.a = "1.0.0-alpha.1", .b = "1.0.0-alpha.beta", .order = -1)
    check_order(.a = "1.0.0-alpha.beta", .b = "1.0.0-beta", .order = -1)
    check_order(.a = "1.0.0-beta", .b = "1.0.0-beta.2", .order = -1)
    check_order(.a = "1.0.0-beta.2", .b = "1.0.0-beta.11", .order = -1)
    check_order(.a = "1.0.0-beta.11", .b = "1.0.0-rc.1", .order = -1)
    check_order(.a = "1.0.0-rc.1", .b = "1.0.0", .order = -1)
    check_order(.a = "1.0.0", .b = "2.0.0", .order = -1)
    check_order(.a = "2.0.0", .b = "2.1.0", .order = -1)
    check_order(.a = "2.1.0", .b = "2.1.1", .order = -1)
    check_order(.a = "1.2.3+x", .b = "1.2.3+y", .order = 0)
    check_order(.a = "999999999999999999999999999.0.0", .b = "1000000000000000000000000000.0.0",
        .order = -1)
    check_order(.a = "1.2.3-9999999999999999999999999", .b = "1.2.3-10000000000000000000000000",
        .order = -1)
    check_order(.a = "1.2.3-A", .b = "1.2.3-a", .order = -1)
    check_order(.a = "1.2.3-9", .b = "1.2.3--", .order = -1)
    check_order(.a = "1.2.3-a.1", .b = "1.2.3-a.1.0", .order = -1)
}

check_valid(.text: StringView) -> () := {
    parsed ::= unwrap_or_abort(.value = semver.parse(.text = text)).result
    if semver.as_view(.self = &parsed).text != text { abort }
}
check_invalid(.text: StringView) -> () := {
    match semver.parse(.text = text) {
        ..error error { if error.reason != ..invalid_input { abort } }
        ..ok _ { abort }
    }
}
check_order(.a: StringView, .b: StringView, .order: Int32) -> () := {
    left ::= unwrap_or_abort(.value = semver.parse(.text = a)).result
    right ::= unwrap_or_abort(.value = semver.parse(.text = b)).result
    if semver.compare(.left = &left, .right = &right).order != order { abort }
    if semver.compare(.left = &right, .right = &left).order != 0 - order { abort }
    if semver.same_precedence(.left = &left, .right = &right).ok != [order == 0] { abort }
    if semver.equals(.left = &left, .right = &right).ok != [a == b] { abort }
}
