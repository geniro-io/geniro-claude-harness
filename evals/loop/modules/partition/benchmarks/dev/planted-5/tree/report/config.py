"""Runtime knobs for the reporting CLI.

Nothing here reaches the rendered table — these are process-level settings read
once at startup.
"""

#: How long a single upstream account fetch may take.
FETCH_TIMEOUT_SECONDS = 15

#: Where the CLI writes its own diagnostics.
LOG_PATH = "/var/log/acme-report.log"

#: Diagnostics verbosity. Hardcoded; see the backlog item about the env var.
LOG_LEVEL = "INFO"
