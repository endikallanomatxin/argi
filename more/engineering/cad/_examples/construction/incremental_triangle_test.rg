-- Use the incremental builder when entities are declared over several steps.
-- Vertices and edges have explicit identities. Closing a triangular boundary
-- creates an open surface, so publication explicitly permits an open model.
test usage_model_builder := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    -- Declare shared entities before assembling their oriented boundary.
    builder ::= t.ModelBuilder()!
    a ::= builder | t.add_vertex($&_, (0.0, 0.0, 0.0))!
    b ::= builder | t.add_vertex($&_, (1.0, 0.0, 0.0))!
    c ::= builder | t.add_vertex($&_, (0.0, 1.0, 0.0))!
    ab ::= builder | t.add_edge($&_, a, b)!
    bc ::= builder | t.add_edge($&_, b, c)!
    ca ::= builder | t.add_edge($&_, c, a)!
    plane: g.Surface#(Float32) = ..plane(
        .value = (
            .origin = (0.0, 0.0, 0.0)
            .normal = (0.0, 0.0, 1.0)
        )
    )
    support ::= builder | t.add_surface($&_, .surface = plane)!
    boundary: [3]t.EdgeUse = ((.edge = ab), (.edge = bc), (.edge = ca))
    face ::= builder | t.add_face($&_, .surface = support, .boundary = view(&boundary))!
    -- Publication transfers ownership; handles are resolved against this model.
    model ::= builder | t.finish_model(~_, .require_closed = false)!
    testing.expect([t.face_id(&model, .face = face)!].value == 0)!
    [
        testing.expect(
            [[t.point(&model, .vertex = [t.vertex_id(&model, .vertex = b)!])!].x == 1.0]
        )!
    ]
}
