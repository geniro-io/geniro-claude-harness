# atomic_state_write — API

Source the helper, then pipe the body in on stdin:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-write.sh"
atomic_state_write "<path>" < body.txt
```

Exit codes: 0 written, 10 unwritable destination, 11 rename failed.
