# The formal backend contract

`formal/verdict.tcl` and `formal/drive.tcl` contain no tool-specific commands.
Everything that talks to a formal tool goes through eleven procs in the
`backend::` namespace, defined by one file per tool:

    formal/backend/<name>.tcl     the Tcl procs, sourced inside the tool
    formal/backend/<name>.sh      how to launch the tool, sourced by run.sh

`run.sh` selects one with `FORMAL_BACKEND=<name>`, looking in
`FORMAL_BACKEND_DIR` (default `formal/backend/`). Left unset, it picks the first
real tool that can run here, and **never** `stub` or `dryrun`: they prove
nothing, so they run only when named. `regress.sh` refuses them outright. Two
ship with the repo:

| backend  | needs a licence | what it is                                        |
|----------|-----------------|---------------------------------------------------|
| `stub`   | no              | fakes the table; drives `formal/tools/smoke.sh`   |
| `dryrun` | no              | prints the calls it would make, proves nothing    |

A backend for a real tool is **not** committed: `.gitignore` excludes everything
in `formal/backend/` except the files above. That also means no git worktree
contains one, so `regress.sh`, which runs every row in a fresh worktree, exports
`FORMAL_BACKEND_DIR` pointing back at this checkout. Keeping the backend outside
the repository entirely (`FORMAL_BACKEND_DIR=~/.formal-backends`) is the
strongest guarantee it is never committed.

## The procs

Build, called by `drive.tcl` in this order:

| proc | arguments | returns |
|---|---|---|
| `backend::clear` | — | — |
| `backend::analyze` | `files defines` | — |
| `backend::elaborate` | `top params` | — |
| `backend::clock` | `expr` | — |
| `backend::reset` | `expr` | — |

`files` is a list of repo-relative paths, `defines` a list of macro names, and
`params` a flat `{NAME VALUE NAME VALUE}` list.

Prove and classify, called by `verdict.tcl`:

| proc | arguments | returns |
|---|---|---|
| `backend::elab_errors` | — | integer count of elaboration errors |
| `backend::prove_all` | — | — |
| `backend::property_list` | `type statuses` | list of property names |
| `backend::design_info` | `kind` | list; `{}` means clean |
| `backend::assumption_status` | — | — (error if unsupported) |
| `backend::report` | `outdir name` | — |

`type` is `assert` or `cover`. `statuses` is a list of spellings to match, so a
rename in one tool release cannot silently drop a whole failure category.
`kind` is currently only `multiple_driven`.

Property names must be the full dotted path ending in the property's own name
(`...u_spec.a_no_loss`). `verdict.tcl` matches expected counterexamples on the
last dotted component, and `regress.sh` greps for `.<name>`; a backend that
returns bare names makes every `cex:` row read NOT CAUGHT.

## The one rule that matters

**A query that cannot be answered must raise a Tcl error. It must never return
an empty list.**

`verdict.tcl` treats an error as exit 2 ("the harness is broken") and an empty
list as a fact about the design. Conflating the two lets a multiple-driver
query that silently returns nothing read as "this design is clean", with every
property that then fails against invented memory contents escalated as a
design defect. If your tool cannot answer `design_info multiple_driven`, raise
an error — do not return `{}`.

`backend::assumption_status` is the one exception: `verdict.tcl` catches its
error and downgrades to a note, because vacuity is still caught by the cover
set.

## Adding a backend

Copy `stub.tcl` and `stub.sh`, and implement the eleven procs against your tool.
The shell half defines three functions:

    backend_available            0 if the tool is runnable here
    backend_prepare  <outdir>    clean stale state; may be a no-op
    backend_launch   <cfg> <outdir> <log>

`backend_launch` must invoke the tool so that it sources `formal/drive.tcl` with
`HWPQ_CFG`, `FORMAL_BACKEND`, `HWPQ_OUTDIR`, and the variables `run.sh` exports
(`FORMAL_BACKEND_DIR`, `HWPQ_SELFTEST`, `HWPQ_UNGATED`) visible in the
environment. It must apply `$TIMEOUT` and propagate the tool's exit code.

`backend::analyze` and `backend::elaborate` must not let a failure escape as a
Tcl error: record it so `backend::elab_errors` returns non-zero, and return.
`drive.tcl` checks between steps and stops with `ELABORATION FAILED:` before
asking the tool to declare a clock on a design that was never built.
