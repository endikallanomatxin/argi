# Standard-library foundations

Implement reusable foundations before application libraries. Preserve explicit
allocation, capabilities, ownership and nominal errors throughout.

## Development order

1. Collections: extend owner-aware algorithms beyond DynamicArray and audit
   structural cleanup on allocation failure and replacement.
2. Streams: byte-level limited adapters and owning line iteration.
3. Filesystem/tools: path normalization, directory walking and CLI options.
4. Numeric/time foundations: elementary float math and UTC calendar conversion.
5. More: hex/Base64, JSON/CSV, then compression/archive consumers.
6. Services/runtime: logging, HTTP, selected hashes/crypto, then concurrency
   and cancellation aligned with the language runtime plans.

Each unit includes executable or negative feature tests and public contracts.
Use application usecases to validate composition. Existing implementations must
be audited before adding parallel APIs; empty sketches do not count as support.
Library-only foundations use existing tokenizing, syntaxing, semantizing and
codegen constructs. Compiler work is justified by a concrete failing consumer.
