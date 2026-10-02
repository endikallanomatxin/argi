https://www.youtube.com/watch?v=gITmP0IWff0&list=WL&t=1252s

There are two algorithms: one runs in linear time and the other in exponential time.

For a long time, nearly all regex engines have used the slower algorithm.

Once regex engines added backreferences, they could no longer use the better algorithm.
As a result, widely used regex engines can be inefficient for large expressions.


RE2 is a modern implementation of the better algorithm:

https://github.com/google/re2/wiki/syntax

I believe Go uses it.
