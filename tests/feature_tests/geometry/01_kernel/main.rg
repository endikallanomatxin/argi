g := import ("engineering/cad/geometry")
t := import ("engineering/cad/topology")
m := import ("engineering/cad/modeling")
s := import ("engineering/cad/sketch")

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stderr
    builder ::= s.SketchBuilder#(.Scalar: Float64)()!!!
    outer ::= [builder | s.rectangle($&_, .width = 2.0, .height = 1.0)]!!!
    drawing ::= [builder | s.finish_sketch(~_)]!!!
    profile ::= s.profile(&drawing, .exterior = outer)!!!
    model ::= m.extrude(&profile, .displacement = (0.25, 0.0, 3.0))!!!
    counts ::= t.entity_counts(&model)
    if counts.vertices != 8 or counts.edges != 12 or counts.faces != 6 { abort }
    if t.is_closed(&model).ok == false { abort }
    base ::= t.face_plane(&model, .face = (.value = 0))!!!
    if base.normal.z >= 0.0 { abort }
    point: g.Point#(Float32) = (1.0, 2.0, 3.0)
    if g.finite_point(point).ok == false { abort }
    status_code = 0
}
