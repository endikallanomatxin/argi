# Orientation and region

`reverse_orientation(&model)` produces an owning immutable model with every
component reversed. This applies to open surfaces as well as closed shells;
closure is preserved, without making any new claim about solid validity.

```rg
inverted ::= t.reverse_orientation(&model)!
restored ::= t.reverse_orientation(&inverted)!
```

A published face's orientation and its oriented boundary walks are coupled.
Reversal toggles `Face.reversed` and every halfedge's `reversed`, exchanges each
halfedge's origin with its old successor's origin, and replaces `next` with its
old predecessor. Supports, curve intervals, p-curves and geometric regions do
not change. P-curves keep their canonical edge parameterization; their traversal
reverses with the use. The relation between face and boundary orientation is
unchanged, including for complementary spherical regions.

Flipping a face flag alone is not this operation. Reversing every component
also preserves opposite edge incidence. There is currently no shell-ID API for
reversing just a selected connected component.

All numeric entity IDs retain their correspondence, including halfedge IDs.
Walks follow `next`, independently of physical record order. Loop anchors and
counts remain unchanged. Applying reversal twice restores topology and geometry
exactly, excluding allocation addresses and ownership domains.

The result has a fresh checked-handle domain, as with other immutable edits.
A checked handle belonging to the source must not be used as a result-domain
handle merely because its numeric ID is unchanged.

The implementation copies the owning arrays and geometry pools, with linear
time and storage. A temporary `O(H)` predecessor index avoids storing persistent
`prev` links or moving records to enforce traversal order. Vertex fan validation
uses that same inverse-link mechanism.
