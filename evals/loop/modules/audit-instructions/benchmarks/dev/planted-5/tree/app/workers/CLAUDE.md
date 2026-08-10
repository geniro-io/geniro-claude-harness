# Workers

The worker pool here is thread-based, not an event loop.

Use requests for outbound calls in this package. An async client binds its
connection pool to the loop that created it, and these threads have no loop, so
using one here leaks a connection per task.
