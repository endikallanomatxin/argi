# Networking libraries

Blocking TCP, UDP, and address resolution are provided by core's `Network`
capability. See `description/168_networking.md` for capability and ownership rules.

- `network/uri` parses borrowed encoded URI components and provides explicit
  encoding, decoding, and owned URI construction.
- `network/http` implements bounded HTTP/1 request parsing, streamed bodies, and
  response writing over byte stream contracts. See [HTTP/1](http/http.md) for its
  API, limits, and a runnable sequential server example.
