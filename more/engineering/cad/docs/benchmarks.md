# Performance measurements

The native Argi executable in `_benchmarks/` measures construction and boundary
traversal for 1, 16, 256 and 4096 spatially separated tetrahedra. Fixed triangle
sizes isolate growth in connectivity from quadratic validation of large faces.
This workload does not measure extrusion or large polygon performance.

From the repository root:

```sh
./zig-out/bin/argi build more/engineering/cad/_benchmarks \
    --release --output /tmp/cad-benchmark
/tmp/cad-benchmark
/usr/bin/time -v /tmp/cad-benchmark
```

Fixture generation, model destruction and CSV printing are outside the timed
intervals. Each size has one unreported warm-up and three reported trials.
Construction includes validation, allocations and copying into owned storage.
Traversal visits all face loops, queries their points and prints a checksum to
keep the computed results observable. It uses the public checked API.

CSV columns report component count, trial, construction and traversal time in
nanoseconds, logical model payload bytes and checksum. Logical bytes are the
sum of stored entity counts times their `size_of`, excluding unused capacity,
container headers, allocator metadata, scratch storage and fixture buffers.
They are not allocated bytes or a peak-memory measurement. `/usr/bin/time -v`
measures peak RSS of the whole process across all sizes, including fixtures and
runtime overhead; it cannot attribute that peak to a particular phase.

Use repeated process runs under comparable compiler, machine and load conditions.
Expect considerable variance, especially for short trials and allocator/cache
warm-up. Record raw output, compiler revision and system details outside the
source tree. This is a baseline tool, not a performance assertion or comparison
against another implementation.

Geometry payload accounting uses the typed pool counts plus the face-to-support
ID map. It does not multiply the public `Surface` union size by the face count:
that union is a query value, not the stored representation. Shared supports are
counted once in their pool.
