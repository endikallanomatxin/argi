# Automatic deinitialization

Owning local values are cleaned up when their lexical scope ends. The compiler
applies a type's `deinit` operation where one exists and performs structural
field cleanup for aggregates without a single destructor. A moved or already
deinitialized Place must not be destroyed a second time; unaffected fields of
a partially moved aggregate remain subject to cleanup. Branches and early
exits must preserve those ownership obligations.

See `38_safety_model.md` for the distinction between a move, deinit, and
physical storage lifetime. Moving cleanup toward a value's last use is a
future optimization, not the current scope rule.
