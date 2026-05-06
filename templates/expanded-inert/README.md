# Template: expanded-inert

This template exercises more of Gas City's documented session model while
remaining deterministic and local-only.

Expected behavior:

- `mayor` and `deacon` are `always` named sessions and should stay active.
- `worker` is a two-slot pool through `min_active_sessions = 2` and
  `max_active_sessions = 2`; both slots should stay active.
- `auditor` is an `on_demand` named session and should remain absent unless a
  command targets it.
- After startup convergence, the Dolt commit count and event count should
  flatten just like the canonical idle test.

The runner is `nix run .#run-idle-path-gc-expanded`. It uses the `gc` already
on `PATH`, waits for four active sessions, and observes for ten minutes by
default.

The active wake runner is `nix run .#run-idle-path-gc-on-demand`. It waits for
the same four-session baseline, runs `checks/wake-auditor.sh`, and then
observes the five-session steady state for five minutes.
