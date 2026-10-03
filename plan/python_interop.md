# Python interoperability

## Direction

Let Python call ahead-of-time compiled Argi libraries. Start with a small
computational consumer using scalars and contiguous numeric buffers; a VM/JIT
or general Python object model is unnecessary for this direction.

## Work to do

- [ ] Support shared-library output and concrete C-callable adapters for Argi APIs.
- [ ] Choose a thin wrapper approach (`ctypes`, cffi, or a CPython extension)
  according to the consumer rather than building a general binding generator.
- [ ] Define capability/allocator supply, buffer lifetimes, native resource
  cleanup, and error translation to Python exceptions.
- [ ] Start with synchronous calls that retain no borrowed Python buffers;
  settle GIL/thread behavior before adding concurrent calls or callbacks.
- [ ] Package and exercise an installable example outside the checkout;
  measure call overhead and data copying for the chosen workload.

Python wrappers belong in more/tooling; reusable native-boundary support belongs
in compiler/core. Embedding Python in Argi, general object conversion, automatic
bindings, and a broad wheel matrix are separate later directions.
