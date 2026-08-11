# Bug report — wrong permissions right after a workspace switch

**Reported by:** support escalation
**Severity:** high (a user was shown controls for a role they do not hold)

## What happens

Right after someone switches workspaces, they briefly see the permissions from
the workspace they just left. One customer reported seeing admin-only controls
in a workspace where their role is viewer. It appears to sort itself out on its
own — if they wait a bit and refresh, the correct permissions come back.

## What we expect

Switching workspaces should show that workspace's permissions immediately.

## What we know

- Reproduced twice in staging by switching back and forth between two
  workspaces where the same account has different roles.
- Logging out and back in also clears it.
- Not everyone hits it, and the people who do say it is short-lived.
- Nothing was deployed to the auth service in the window the reports started.

## What we do not know

- Whether the wrong permissions are ever *written* anywhere, or only displayed.
- Whether it is specific to accounts that belong to more than two workspaces.
