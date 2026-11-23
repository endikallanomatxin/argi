# Result ownership across a join

Build the directory and run its output. Exit 0 requires all three destruction
observations. The direct call drops one ticket. Awaiting the first task moves
its ticket into the caller, whose scope exit drops it. A second await must
report already_awaited. Dropping a moved future must join the second task and
drop its unclaimed ticket. The expected final count is three. Counter checks
follow synchronous return, successful await or completed scope cleanup.

The worker takes no inputs. Its returned ticket contains a scalar and carries a
cleanup responsibility. Exit 2 records the current unsupported result. Exit 3
indicates failure to start and exit 4 indicates an executor mismatch. A run
ending at submission only exercises the direct-call control.

The existing collection slot operations distinguish establishing storage,
initializing a slot and moving an owner out. A native task output is allocated
before worker entry. Its zero-filled bytes cannot supply a previously
initialized owner for replacement cleanup. The worker must initialize empty
storage; after verified publication the consumer can move the result out or
run its cleanup in place. A failed join provides evidence for neither action.
