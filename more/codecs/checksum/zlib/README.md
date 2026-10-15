# zlib checksums

`crc32` calculates a CRC over a read-only initialized byte view. `update_crc32`
continues a previous result, allowing several chunks to be processed without
copying. Empty chunks leave the previous CRC unchanged. Results use `CULong`,
matching zlib's unsigned-long result; only its low 32 bits carry the CRC.

The wrapper requires a live `ffi` capability. It borrows the view for the call,
passes exactly its byte extent, and never retains its address. It does not
allocate or transfer storage, and creates no references from foreign addresses.
CRC detects accidental corruption and is not a cryptographic integrity check.

Install a system zlib with `crc32_z` (zlib 1.2.9 or newer) and add to the consuming
package's `argi.toml`:

```toml
[[native]]
library = "z"
```

Import `codecs/checksum/zlib`, then call `zlib.crc32(&source)` or
`zlib.update_crc32(previous, &source)` with `assume ffi := system.ffi` in scope.
The [zlib manual](https://zlib.net/manual.html) defines the foreign contract.
Compression streams and owned zlib handles are outside this module's scope.
