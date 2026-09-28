Codecs is a name for englobing a set of modules that are used to encode and decode data:

- `archive` Formats for compressing folders.
- `compression` Formats for compressing files.
- `encoding`
- `serialization`


Link against zlib.
- What it provides: DEFLATE compression and decompression (gzip, PNG, ZIP).
- Why it matters: it is the standard for compressed network data, file formats, and embedded systems. Nearly any project with heavy I/O links it dynamically for maximum speed without reimplementing the algorithm.

Link against FFmpeg (libavcodec / libavformat / libavutil).
- What they provide: audio and video codecs (H.264, VP9, AAC…), container wrappers (MP4, MKV), and assorted utilities.
- Why they matter: streaming servers, video editors, media players, and even games use FFmpeg to transcode, extract frames, or mix tracks without writing codec assembly code.
