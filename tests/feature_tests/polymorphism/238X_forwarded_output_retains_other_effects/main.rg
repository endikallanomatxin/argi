Editor: Abstract = (
    edit(.self: &Self, .target: $&Int32, .other: $&Int32, .change: Bool, .change_other: Bool) -> (
        .auxiliary : ?Int32,
        .result    : ?Int32
    ) where {
        on auxiliary ..some { invalidates(other) }
        on auxiliary ..none {}
        on result ..some { invalidates(target) }
        on result ..none {}
    }
)

Cell: Type = (.unused: Int32)

Cell implements Editor

edit(
        .self         : &Cell,
        .target       : $&Int32,
        .other        : $&Int32,
        .change       : Bool,
        .change_other : Bool
    ) -> (
        .auxiliary : ?Int32,
        .result    : ?Int32
    ) := {
    if change_other {
        other&= 55
        auxiliary = ..some(.value = 55)
    } else {
        auxiliary = ..none
    }

    if change {
        target&= 42
        result = ..some(.value = 42)
    } else {
        result = ..none
    }
}

forward(.editor: &Virtual#(Editor), .target: $&Int32, .other: $&Int32) -> (.result: ?Int32) := {
    returned ::= edit(editor, target, other, false, true)
    result = returned.result
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    editor ::= to_virtual#(Editor)(&cell)
    target :: Int32 = 41
    other :: Int32 = 54
    previous ::= &other
    outcome ::= forward(&editor, $&target, $&other)

    match outcome {
        ..none { if previous&!= 54 { status_code = 1 } }
        ..some _ { status_code = 2 }
    }
}
