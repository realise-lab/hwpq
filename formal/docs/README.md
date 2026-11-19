# Formal verification suite for HWPQ

One interface-only specification binds unchanged to every architecture in the
library, so adding a design to the suite costs two short files. Eight
architectures are proved across fifteen configurations.

This document is the manual: how to run the suite, what a module must do to be
provable by it, and how to add one. What the suite found, and the justification
for the resulting RTL and testbench changes, is in [`results.md`](results.md).
The backend contract is in [`../backend/README.md`](../backend/README.md).

## 1. What this proves, and what it does not

The spec is a protocol and ordering contract over the six-port interface: a
command is accepted only when the matching ready is high, occupancy tracks the
commands actually accepted, the head is the maximum resident element, and no
element is lost or duplicated. White-box addenda add per-module claims the
interface cannot see.

The hybrid is proved in two halves that share `spec/hybrid_tree_contract.sv`.
`hybrid_tree_pair` proves its pair tree meets the contract, and
`hybrid_systolic_heap_standin` proves the hybrid over stand-in trees that assume it.
Both run at the same tree size, so together they cover the whole design.

It does not prove throughput, timing, area, or anything about `hybrid_tree`,
which is outside both the simulation suite and formal scope. Proofs run at small
geometry (`QUEUE_SIZE=7`, `DATA_WIDTH=3` or less) because the properties are
about protocol, not width.

## 2. Quick start

No tool is named in tracked files. `run.sh` sources
`$FORMAL_BACKEND_DIR/<name>.{sh,tcl}`, defaulting to `formal/backend/`.

```bash
FORMAL_BACKEND=<name> formal/run.sh register_array             # prove one config
FORMAL_BACKEND=<name> formal/run.sh --selftest register_array  # expect "self-test PASSED"
FORMAL_BACKEND=<name> formal/run.sh --all                      # every config
FORMAL_BACKEND=<name> formal/run.sh --ungated register_array   # drop workaround assumptions
FORMAL_BACKEND=stub   formal/run.sh --all                      # licence-free; proves nothing
formal/tools/smoke.sh                                          # harness check; needs verilator
```

Flags: `--all`, `--selftest`, `--ungated`, `--timeout <seconds>`.

`stub` and `dryrun` ship so the harness can be exercised without a licence.
Unset, `FORMAL_BACKEND` picks a real tool and never falls back to either;
`regress.sh` refuses them outright.

A self-test passes only if `a_selftest_must_fail` is reported as a
counterexample. A nonzero exit alone is not enough, since an elaboration error
also exits nonzero.

Everything a run generates goes to
`formal/fv_proj/<module>[_selftest][_ungated]/` and nowhere else.

## 3. Layout

| Path | What it is |
|---|---|
| `run.sh` | single-config driver |
| `drive.tcl` | reads a `.cfg` and builds the model |
| `verdict.tcl` | turns the property table into an exit code |
| `config/*.cfg` | per-proof configuration, data not Tcl |
| `bind/*.sv` | per-module bind plus reset harness |
| `spec/hwpq_spec.sv` | the portable specification |
| `spec/hwpq_*_aux.sv` | white-box addenda |
| `backend/` | the thirteen-proc backend contract |
| `tools/regress.sh` | mutation sweep and baseline driver |
| `tools/smoke.sh` | licence-free harness check |

The real tool's backend is local-only and gitignored. **Never commit it**, and
keep it out of archives.

## 4. The contract a module must satisfy

**The uniform interface.** Every architecture exposes the same six ports, with
the command encoded as `{i_wrt, i_read}`:

```
i_CLK, i_RSTn, i_wrt, i_read, i_data  ->  o_write_ready, o_read_ready, o_data
```

`10` enqueue (only when `ENQ_ENA=1`), `01` dequeue, `11` replace.

**Readies.** Each command waits on its own ready: enqueue on `o_write_ready`, dequeue and
replace on `o_read_ready`. A replace on an empty queue waits on `o_write_ready` and inserts; a
replace-only build takes a replace on either ready. Either ready
may drop alone while the DUT is busy, and a refused command has no effect. A high ready is
honest, and both are exact once the caller has been quiet for `MAX_SETTLE` cycles; a stream
of commands may hold one low. `settled` (`o_write_ready || o_read_ready`) is low only while
both are.

**Readies depend on state only.** A ready that is ANDed with `!(i_wrt || i_read)`
deadlocks a master that holds a command valid until ready.

**Reserved sentinels.** `'0` is the empty slot and the dequeue mechanism.
All-ones is the max-priority placeholder a replace-only build resets into.
Neither is legal on `i_data` in any build, so the payload alphabet is
`2**DATA_WIDTH - 2` values everywhere.

## 5. The shared specification

`spec/hwpq_spec.sv` reads only the six ports, which is what lets it bind
unchanged to every module. White-box claims go in separate addenda so the
portable spec never acquires module-specific dependencies.

Configuration is entirely through bind parameters:

| Parameter | Meaning |
|---|---|
| `ENQ_ENA` | is the enqueue datapath present |
| `HAS_BUSY` | do both readies drop mid-operation |
| `HAS_FULL` | does `!o_write_ready` mean full, or only busy |
| `CAPACITY` | how many elements the DUT actually holds |
| `MAX_SETTLE` | worst-case cycles a quiet DUT takes to make both readies exact |
| `ASSUME_FILL_FIRST` | assume a replace-only queue is filled before any read |

Pass `MAX_SETTLE` from the DUT's own localparam where one exists, so it tracks
`QUEUE_SIZE`. Where no such localparam exists the value is hand-derived and does
not track geometry: re-derive it when the walk structure or `QUEUE_SIZE`
changes.

**Every assumption is a hole, and the cover set is the only detector.** An
assumption that is too weak fails loudly; one that is too strong proves
everything vacuously with a fully green table.

## 6. Adding an architecture

1. Write `bind/<module>_bind.sv`: a reset harness declaring `i_init_RSTn` as the
   elaboration top, and a `bind` of `hwpq_spec` with the parameters above. The
   tool holds the declared reset inactive after init, so declaring a separate
   init reset keeps the DUT's `i_RSTn` free for mid-operation resets.
2. Write `config/<module>.cfg`. Keys: `source`, `top`, `param`, `clock`,
   `reset`, `module`, `allow_bounded`, `expect_cex`, `expect_cex_ungated`, and
   `helper` for a stage of white-box asserts to prove first and then assume;
   stages run in config order.
3. Run `--selftest`, then the proof.
4. If the module keeps internal state the interface does not determine, add a
   white-box addendum and a second bind.

`formal/tools/template/` generates the skeleton.

## 7. When a run fails

**Read the elaboration warnings before the property table.** On a newly bound
module the harness is the newer, less exercised artifact and deserves suspicion
before the design does. A multiply-driven RAM model lets the tool choose the
memory contents, which fails properties for reasons that say nothing about the
design — and it is announced at elaboration, not in the table.

The verdict fails on an elaboration error, a multiply-driven design, unreachable
covers, and an empty assert table, which means a bind that never attached.

Counterexamples are evidence that *something* is wrong. Check in this order:
the bind parameters, then the spec's assumptions, then the RTL.

## 8. Regression mechanisms

`tools/regress.sh --all` reverts each recorded fix at current HEAD and checks the
suite still catches the defect. `tools/mutations/SWEEP.tsv` is the manifest; its
first line lists the comment-only commits to revert before each row, newest
first, and must be updated whenever a comment-only commit lands.

`tools/regress.sh --baseline --all` proves the pre-verification RTL from
`tools/baseline/MANIFEST.tsv`, which pins fixed historical commits and is
unaffected by changes at HEAD.
