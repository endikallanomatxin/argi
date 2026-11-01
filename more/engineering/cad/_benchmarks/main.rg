t := import ("engineering/cad/topology")
g := import ("engineering/cad/geometry")

_type_size := #(.T: Type) () -> (.bytes: UIntNative) { bytes = size_of(.type = T) }

-- Build once with --release. Timings exclude fixture generation and printing.
-- Independent tetrahedra keep all face sizes fixed as the dataset grows.
_run := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_

    assume writer ::= $&system.terminal&.stdout
    sizes: [4]UIntNative = (1, 16, 256, 4096)
    base: [4][3]UIntNative = (
        (0, 2, 1),
        (0, 1, 3),
        (1, 2, 3),
        (2, 0, 3)
    )
    print("components,trial,construction_ns,traversal_ns,logical_payload_bytes,checksum")!
    for count in sizes {
        points ::= DynamicArray#(g.Point#(Float64))(.capacity = count * 4)!
        faces ::= DynamicArray#([3]UIntNative)(.capacity = count * 4)!
        component :: UIntNative = 0
        x :: Float64 = 0.0
        expected_checksum :: Float64 = 0.0
        while component < count {
            offset ::= component * 4
            push($&points, .value = (x, 0.0, 0.0), .allocator = allocator)!
            push($&points, .value = (x + 1.0, 0.0, 0.0), .allocator = allocator)!
            push($&points, .value = (x, 1.0, 0.0), .allocator = allocator)!
            push($&points, .value = (x, 0.0, 1.0), .allocator = allocator)!
            for face in base {
                row: [3]UIntNative = (offset + face[0], offset + face[1], offset + face[2])
                push($&faces, .value = row, .allocator = allocator)!
            }
            expected_checksum = expected_checksum + 12.0 * x + 9.0
            x = x + 3.0
            component = component + 1
        }
        trial :: UIntNative = 0
        while trial < 4 {
            start ::= monotonic_now(.self = system.clock)!
            model ::= t.from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
            built ::= monotonic_now(.self = system.clock)!
            counts ::= t.entity_counts(&model)
            checksum :: Float64 = 0.0
            face :: UIntNative = 0
            while face < counts.faces {
                id ::= face | convert#(.to: t.FaceId)(_)
                for entry in t.loop_halfedges(&model, .loop = t.face_loop(&model, .face = id)!)! {
                    p ::= t.point(&model, .vertex = t.halfedge_vertex(entry.halfedge)!)!
                    checksum = checksum + p.x + p.y + p.z
                }
                face = face + 1
            }
            end ::= monotonic_now(.self = system.clock)!
            if checksum != expected_checksum { abort }
            build_time ::= elapsed(.start = start, .end = built)!
            traversal_time ::= elapsed(.start = built, .end = end)!
            payload ::= counts.vertices * _type_size#(g.Point#(Float64))()
            payload = payload + counts.edges * _type_size#(t.Edge)()
            payload = payload + counts.halfedges * _type_size#(t.HalfEdge)()
            payload = payload + counts.loops * _type_size#(t.Loop)()
            payload = payload + counts.faces * _type_size#(t.Face)()
            payload = payload + t.geometry_storage_info(&model).payload_bytes
            -- Trial zero warms the complete construction and traversal paths.
            if trial > 0 {
                print(count, .terminator = ",")!
                print(trial, .terminator = ",")!
                print(nanoseconds(&build_time).value, .terminator = ",")!
                print(nanoseconds(&traversal_time).value, .terminator = ",")!
                print(payload, .terminator = ",")!
                print(checksum)!
            }
            trial = trial + 1
        }
    }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    _run(.system = system) handle failure { status_code = 1 }
}
