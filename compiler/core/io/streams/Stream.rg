InputStream#(.line: Type) : Abstract = (
    read_line(.self: $&Self) -> (.line: line)
)

OutputStream#(.text: Type) : Abstract = (
    write(.self: $&Self, .text: text) -> ()
    flush(.self: $&Self) -> ()
)

-- TODO:
-- Reached arguments with mutable pointer types such as `$&OutputStream#(...)`
-- still need a dedicated compiler pass for end-to-end call resolution. The
-- capability shapes are in place; add the direct reached-stream tests once
-- mutable reached arguments resolve as smoothly as value reaches.
