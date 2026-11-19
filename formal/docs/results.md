# Formal verification of the HWPQ library: results

What was verified, what it found, and the justification for each change made to the RTL and to the testbenches. The harness itself, including how to run it and how to bind a new architecture, is documented in [`README.md`](README.md).

Findings keep their original `F-n` numbers. They label rows in the regression manifests and sections of this document, and are never reused. They are not cited in code comments, which state the rule rather than the incident behind it. Each heading below is an anchor: `results.md#f-32` resolves.

## 1. Summary

Seven of the library's eight architectures are proven against a shared, interface-only specification that binds to each of them unchanged. The eighth, `hybrid_tree`, does not compile under the open-source toolchain and is out of scope. The seven are covered by thirteen proof configurations, which differ by `ENQ_ENA` build and, for `systolic_array`, by white-box addendum. All thirteen pass. The proofs need a licensed tool and are run on demand through `formal/run.sh --all`; CI runs the simulation suite only.

The design as it stood when verification began does not. Run against the current harness, the pre-verification RTL at `af089e5` gives:

| configuration group | result at baseline |
|---|---|
| `register_array`, `register_array_pipelined`, `register_tree`, `register_tree_pipelined` | clean |
| the same four as replace-only (`ENQ_ENA=0`) builds | the documented fill-before-read contract, not a defect (F-1) |
| `systolic_array`, 3 configurations | five black-box assertions fail; a sixth defect prevents elaboration entirely |
| `bram_tree_pipelined` | six of eight black-box assertions fail |
| `bram_tree` | nine assertions report "proven" while fifteen of twenty covers are unreachable |

Seventeen `fix()` commits were made to the RTL, addressing fifteen distinct findings. Two of those findings were subsequently retracted after measurement, and one further is a retraction candidate; section 4 gives the disposition of each. Eight commits changed the simulation suite, each traceable to a defect the proofs found and simulation could not; these are in section 3.

Two further defects were located in the specification rather than in the design, and one in the RAM model shared by both BRAM modules. The first two are documented in [`README.md`](README.md) under triage, since they are guidance for future contributors rather than results about this library. The third is F-21, below, because it required a change to a design file.

One caveat applies to the baseline table and is stated once. The baseline is not the design as originally written. Before `e7c20ad` the modules exposed `o_full` and `o_empty`, which are different signals on different paths, and the uniform six-port interface is itself part of this work. The claim the table supports is narrower: the design as it stood when verification began, once a common interface existed.

## 2. Changes to the RTL, by module

Ordered by the number of findings, ascending.

### 2.1 The register family

`register_array`, `register_array_pipelined`, `register_tree` and `register_tree_pipelined`, in both `ENQ_ENA` builds, at `QUEUE_SIZE=4` and `QUEUE_SIZE=7` respectively with `DATA_WIDTH=3`. These four are the soundest modules in the library. They are clean at baseline in their enqueue-capable builds and carry one finding between them, which is a contract question rather than a defect and was contained rather than repaired.

#### F-1: a replace-only queue advertises data it cannot deliver

`94526ac` for the four register modules; `df82ed2` extends the same containment to `bram_tree_pipelined`.

In a replace-only build, reset fills every slot with the maximum-priority placeholder while `size` resets to 0, so the queue boots physically full and logically empty:

```verilog
assign reset_queue[i] = '1;   // ENQ_ENA=0
```

A replace writes the payload into the head, but `'1` outranks it, so the sort network immediately sinks the payload below the remaining placeholders. The head is still a placeholder while `size` reports 1. The two arms are counting different things:

```verilog
// replace: counts SLOTS CONSUMED
3'b001:
next_size = (o_data == '1 && !ENQ_ENA)    ? size+1 : //special case since reset fills up the pq with highest prio item
            (size == '0 && i_data != '0) ? size+1 :
...
// dequeue: asks nothing about what actually left
3'b010: 
next_size = (empty) ? size :
            size - 1;
```

`size` counts slots consumed, while `o_read_ready` promises elements retrievable. Those differ for exactly as long as a placeholder outranks the caller's data, and the state is reachable in two cycles from reset. The design is internally inconsistent about this independently of any documentation: if the intended contract is fill-before-read, the queue should report empty throughout the fill phase, but `size` increments on the first replace and invites a read it cannot service.

The containment gates the port on the head, under `ENQ_ENA` so the comparator constant-folds away in enqueue-capable builds:

```verilog
assign o_read_ready = !empty && (ENQ_ENA || o_data != '1);
```

Two things follow. The port never advertises a sentinel as data, which `a_head_not_placeholder` proves. And because every module derives its dequeue from `o_read_ready`, a contract-violating read during the fill phase is inert rather than popping a placeholder and decrementing `size`.

What containment does not do is make the resident elements servable. `o_read_ready` is one bit answering two questions, "do you hold an element" and "is your head a real element", and this design makes them disagree. The original RTL answered the first and was wrong about the second; the gate answers the second and is wrong about the first. The residual is scoped by `ASSUME_FILL_FIRST` and recorded as CH-4.

Two alternatives were rejected. Resetting to `'0` rather than `'1` does not work: from an all-zero array a second replace overwrites the first payload instead of consuming a slot, because that path is size-neutral, so the queue would hold one element indefinitely and never fill. A max-priority placeholder is visible at the head, which is what lets the design tell "this replace consumed a free slot" from "this replace swapped a real element" by reading `o_data` alone; a min-priority placeholder hides where the head cannot see it. The disagreement is structural. Validity bits are the only remaining repair and were declined on 2026-08-30: the cost is a design change across five modules and every synthesis number this library exists to compare, against closing a gap no caller following the documented contract can reach.

Containment is the terminal disposition. Reopening F-1 requires a caller that violates the contract and is harmed by the inert result, which would be a new finding.

Extending the gate to `bram_tree_pipelined` produced a standing rule. Gating the port alone would have left `cmd_dequeue` accepting a dequeue that `o_read_ready` no longer advertises, which is F-22 pointing the other way. When a ready is gated, the command it guards is gated in the same commit, or the reason not to is stated.

### 2.2 `systolic_array`

Proven at `QUEUE_SIZE=8, DATA_WIDTH=3` across three configurations: the black-box specification, and two white-box addenda written to isolate specific questions. Three findings, of which one prevented the module from being verified at all and one is the most serious defect in the effort.

Its usable capacity is `QUEUE_SIZE-2`, a shift-chain margin measured under F-9 rather than assumed. This is a live design fact, and both the testbench shim (`TB_CAPACITY`) and the bind (`CAPACITY`) carry it.

#### F-6: the module did not elaborate under the tool, due to out-of-range array reads

`3c8cd30`.

The sorting loop runs over `HALF_SIZE` and indexes two groups of arrays: the cell arrays, sized `HALF_SIZE`, and the gap arrays, one per adjacent pair and therefore one element shorter. It reads both at `[i-1]`, `[i]`, `[i+1]` and `[i+2]`. A static sweep of the loop body at `QUEUE_SIZE=8` finds 47 reference sites out of range for at least one value of `i`. Most are pruned by short-circuit terms the author wrote. Two were not:

```verilog
if (!(IB_shift[i-1] && IB_shift_valid[i-1])) IB[i] <= MIN_VALUE;
//               ^^^ index -1 at i=0, array is [0:2]

IB_greater_than_OB_next[i] && (!IB_greater_than_OB[i+1])
&& ((IB[i+1] == 0) || (IB_greater_than_OB_next[i+1]) || (IB_shift[i+1])) && IB_shift_valid[i]: begin
//                                             ^^^ index 3 and 4, array is [0:2]
```

Elaboration fails with `VERI-1216`, so nothing binds and no property runs.

Simulation never noticed because an out-of-range read of a four-state unpacked array returns X, every dependent condition goes X, `if (X)` does not fire, and a `priority case (1'b1)` with X selectors takes no branch. Under iverilog these sites are silently inert; the module compiles and both its testbenches pass. This is the sharpest instance of a general pattern: simulation tolerates what formal will not load.

The obvious repair, tightening the loop bound so the gap arrays are always in range, is wrong. At the top index one arm reads a `HALF_SIZE`-long array and its negated term is constant-true there:

```verilog
IB_greater_than_OB[i] && !(i < (HALF_SIZE-1) && OB_shift[i] && OB_shift_valid[i]): begin
```

That arm performs a real swap of the last pair, so dropping the iteration would change behaviour. The fix is therefore per-site: six arms whose selector reads a gap array take an `(i < HALF_SIZE-1)` guard, which reproduces the X-selector behaviour exactly, the arm above is deliberately left unguarded, one site takes `i > 0`, and two terms are read as zero.

Fixing one site exposed another, and the two were found in successive runs. `tools/mutations/SWEEP.tsv` therefore requires exactly two distinct `VERI-1216` errors on the revert, so a regression leaving one site guarded does not register as caught.

The result was validated rather than assumed. Simulation output is byte-identical before and after on the full shared testbench at `QUEUE_SIZE=16`, a different geometry from the proof, so the guards are exercised at two sizes. Checked with the simulator available on the proof machine, since neither iverilog nor verilator is installed there.

#### F-8: asserting `i_wrt` while the queue was full corrupted it

`4656397`.

The main enqueue datapath refuses a write when full:

```verilog
if (i_wrt && !i_read && !full) begin
  ...
  IB[0] <= i_data;
```

The sorting network reacts to `i_wrt` directly, with no `full` guard, in three places:

```verilog
// suppresses the CLEAR that would have vacated IB[0]
if ((i == 0 && !i_wrt) || (i > 0 && !IB_shift_valid[i-1])) IB[i] <= MIN_VALUE;

// performs the WRITE the datapath refused
if (i == 0 && i_wrt) begin
  if (i_data > OB[0] && !i_read) begin
    IB[i] <= OB[0];
  end else begin
    IB[i] <= i_data;
  end
end

// suppresses it again
if ((i > 0 && (IB_shift_to_OB[i-1] || IB_greater_than_OB[i-1])) || (i == 0 && !i_wrt)) begin
  IB[i] <= MIN_VALUE;
end
```

So a write the datapath refused still injected `i_data` into `IB[0]` and still suppressed the clear that would have vacated it. Whatever `IB[0]` held was destroyed, and cells were left holding values the size counter did not account for.

Two white-box properties in `formal/spec/hwpq_systolic_clobber.sv` detect it, counting physical cells rather than reading the ports:

```verilog
// no copy of the tracked value disappears without a pop to account for it
a_no_clobber : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
    past_valid |-> ($past(phys_count) - phys_count) <= ($past(pops_tv) ? 1 : 0));

// no cell holds a value the size counter does not know about
a_no_ghost_cells : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
    settled |-> live_cells <= size);
```

The second is not a side check. `phys_count` counts cells, which is a sound proxy for copies held only if the array never strands stale ones, so `a_no_ghost_cells` is what makes `a_no_clobber` mean what it says.

The cause was isolated by three configurations:

| writes constrained by | `a_no_clobber` | `a_no_ghost_cells` |
|---|---|---|
| nothing | counterexample | counterexample |
| `!full` only, so writes inside the F-7 window are allowed | proven | proven |
| `o_write_ready`, a compliant caller | proven | proven |

The middle row is decisive: the window is innocent, and `i_wrt` while full is the entire cause.

The fix names what the datapath actually does, and the three sites use it instead of raw `i_wrt`:

```verilog
wire writing_ib0 = i_wrt && (i_read || !full);
```

Both properties then prove to unbounded depth with writes completely unconstrained, which is the statement worth having: a refused command is inert. That is what every other module in the library already did, and what both the shared testbench and the portable specification had assumed without stating.

Simulation output is byte-identical at `QUEUE_SIZE=16` with and without the fix, differing only in elaboration statistics by the one added wire, and the F-9 margin sweep is unchanged in every cell.

This finding is also the case for retaining `--ungated`. When the fix landed, the ungated run failed reporting an expected counterexample that no longer fired, which is the prompt to retire the assumption. No one had to remember the workaround existed.

#### F-7: the module accepted enqueues it advertised as refused

`baafe9b`.

The module had two capacity thresholds one slot apart:

```verilog
assign o_write_ready = !(size >= (QUEUE_SIZE - 3)) && (o_data != MIN_VALUE || empty);
assign full  = (size >= QUEUE_SIZE - 2);
...
// the ACTUAL gate
// compute size_next
if (i_wrt && !i_read && !full) begin
  size_next = size + 1;
```

At `size == QUEUE_SIZE-3` the queue reported not-ready and then accepted the write anyway. The advertised ready was not the acceptance predicate.

This broke the specification before it implicated the design, because the spec reconstructs "the DUT took this command" from the matching ready:

```verilog
wire acc_enq = settled && ENQ_ENA && cmd_enqueue && o_write_ready;
```

That is exact for the four register designs, which gate acceptance on the ready they advertise, but it is a premise about those DUTs rather than a fact about the interface. Here the specification scored an accepted enqueue as refused, its counter never recorded the element, and four assertions failed. Reading the counterexample is what separated a specification bug from an RTL bug: `size` increments, so the DUT took the write, while the model's count does not, and one cycle later the head is the tracked value while the model believes no copy is resident.

The window was then characterised as exactly one slot wide, reachable in six cycles, and shown harmless by the `!full`-only configuration under F-8. Both intuitive readings were wrong: it looks like it consumes the slack the shift chain needs, and the four failing assertions look like the consequence, but the assertion failures were the model undercounting and the data loss was F-8, a separate defect.

It was fixed nonetheless, because it cost a usable slot for no benefit, by making the two structurally the same signal rather than two numbers that happen to agree:

```verilog
assign o_write_ready = !full && (o_data != MIN_VALUE || empty);
```

Deriving it from `full` is the point. Reconciling them at equal numeric values would have left the same failure mode one edit away. The white-box addendum no longer measures the window, since there is none, and asserts the invariant instead:

```verilog
a_ready_matches_accept : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
    settled |-> (o_write_ready == !full));

a_size_bounded : assert property (@(posedge i_CLK) disable iff (!i_RSTn)
    size <= QUEUE_SIZE - 2);
```

Direction mattered and the obvious choice was wrong. The reading that the third slot must be load-bearing argues for tightening `full` to `QUEUE_SIZE-3`. The margin sweep under F-9 shows the opposite: margin 2 is sufficient and margin 1 wedges, so the correct move is relaxing `o_write_ready` to match `full`. That recovers a slot rather than costing one, taking usable capacity from `QUEUE_SIZE-3` to `QUEUE_SIZE-2`.

`ASSUME_ENQ_WHEN_WREADY` is retired for this module as a result, closing CH-5. With the two signals coupled, the specification's ready-based acceptance decode is exact and the proof holds with no constraint on when the caller may write. The parameter remains in `hwpq_spec.sv`, defaulted off, for the next module with this shape.

### 2.3 `bram_tree_pipelined`

A replace-only tree (`ENQ_ENA=0`) whose nodes are held in block RAM and sorted by a multi-cycle sift walk. Its defects fall into two groups. The BRAM has no reset port, so any assumption the design makes about initial memory contents must be established explicitly. Separately, the ready ports, the command decode, and the occupancy counter each derived the condition "the walk has finished" from a different signal.

The module passed its testbench throughout.

#### F-21: the dual-port RAM model was multiply driven, so memory contents were tool-selected

`a7fb6c3`, and `b6d05fa` for the copy under `bram_tree`.

`rams_tdp_rf_rf.sv` is the vendor true-dual-port template, and it assigned the memory array from two `always` blocks, one per port:

```verilog
always @(posedge clka) begin
  if (ena) begin
    if (wea) ram[addra] <= dia;
    doa <= ram[addra];
  end
end

always @(posedge clkb) begin
  if (enb) begin
    if (web) ram[addrb] <= dib;
    dob <= ram[addrb];
  end
end
```

Simulation is unaffected, because the ports write different addresses and the non-blocking assignments never race. A formal tool must resolve the drivers instead. The tool reported every bit of the array as multiply driven and treated writes as unobservable, so a write to address 0 was not required to be present in the array on the following cycle. It was announced on every run from the first:

```
[WARN (VDB-1000)] rams_tdp_rf_rf.sv(36): net 'ram[6][2]' is constantly driven from multiple places
INFO (IMDS005): Number of multiple-driven bits in design: 21
```

Every memory-dependent property on the module had been proved against that model. Six counterexamples became proofs once it was corrected, with no change to the design's logic:

| property | before | after |
|---|---|---|
| `a_root_outranks_children`, the heap invariant | cex 155-188 | proven |
| `a_occ_bounded` | cex 117 | proven |
| `a_occ_empty_agrees` | cex 158 | proven |
| `a_no_loss` | cex | proven |
| `a_size_not_overstated` | cex 18-23 | proven |
| `a_reset_restores_fill` | cex | proven |

The heap violation had been recorded as the most serious thing known about the module and had been scheduled for rework of the sift walk's compare and write-back logic. It does not exist, and neither does the occupancy overflow.

The fix drives the array from a single process. It is a precondition for verifying either BRAM module, and `tools/mutations/SWEEP.tsv` reverts it on both to confirm the harness still refuses a multiply-driven design rather than proving properties about it.

#### F-22: the module advertised a dequeue its own decode would discard

`7bb8d9c`.

```verilog
assign o_write_ready = sift_done;
assign o_read_ready  = !(queue_size == 0) && root_done;
//                                        ^^^^^^^^^ different signal
```

`root_done` rises on the root write-back at the start of the sift walk. `sift_done` rises only when the walk terminates, up to `TREE_DEPTH-1` levels later, and `cmd_dequeue` was gated on `sift_done`. Between those two events the module advertised a read it would discard: the caller observes the ready, asserts `i_read`, and no state changes.

Gating the port on `sift_done` has no cost, since no command could be accepted in that window. The later reset work (`d84465e`) folded both sides into one named term, used by the ports and by the decode so they cannot drift apart again:

```verilog
assign accept_ok = sift_done && !filling;
assign cmd_dequeue = !i_wrt && i_read && accept_ok && (queue_size != 0) && head_servable;
assign o_write_ready = accept_ok;
assign o_read_ready  = !(queue_size == 0) && accept_ok && head_servable;
```

This is the F-7 defect on a second architecture. Closed in simulation at `fdb7003`; see section 3.

#### F-25: reset never restored the placeholder fill

`d84465e`.

The BRAMs have no reset port, and the block that writes the all-ones placeholder fill is simulation-only:

```verilog
initial begin
  // on initialization, set all values to be of highest priority
  for (int i = 0; i < DEPTH; i++) begin
    ram[i] = '1;
  end
end
// VERI-1060: 'initial' construct is ignored
```

Synthesis takes it as a power-up value and a formal tool ignores it outright, which `VERI-1060` reports on every run. Nothing restored the fill. A reset arriving with data in the queue cleared the registers and set `queue_size` to 0 while leaving the memory holding live nodes, producing a queue that reports empty while its interior nodes hold data, which the next replace then sorts against.

The fix is a reset fill sequencer. `filling` is set on every reset deassertion and sweeps the placeholder across all `NODES_NEEDED` addresses before any command is accepted. `FILL_LAST` is one address past the last, because `addr`, `din` and `we` are themselves registered, so the write issued at `NODES_NEEDED-1` does not commit until the following cycle.

Simulation could not check this by construction: the testbench reset once, at time zero. Closed at `a19e95e`.

#### F-24: the replace arm counted past `QUEUE_SIZE`

`e0cec3a`.

```verilog
if (o_data == '1) begin //special case for following a reset, we need to replace all the values in
  next_queue_size = queue_size + 1;
```

`o_data == '1` was read as "still in the fill phase", during which each replace does evict one placeholder and add one element. The root can, however, hold a placeholder while the queue is already occupied, because the sift walk can sink a real element below one. In that state the arm counts an insert for which the queue has no room, and `queue_size` runs past `QUEUE_SIZE`. The guard restores the symmetry the dequeue path already had:

```verilog
if (o_data == '1 && queue_size < QUEUE_SIZE) begin
```

The same unguarded all-ones arm exists in the register family, where it is recorded as out-of-range behaviour rather than a defect, because reaching it there requires the caller to drive a reserved value. Here the module reaches the state unaided from legal inputs. The same code shape has a different verdict on different modules according to reachability, which is the argument for deciding such cases by proof rather than by inspection. Appendix A records the register-family case.

This fix is a retraction candidate. The sweep reverts it and nothing in the suite reddens, and `a_no_placeholder_at_capacity` proves, so the overflow state is unreachable. The original counterexample appears to have been an F-21 artifact. The guard is retained; section 4 gives the reasoning, which parallels F-23.

#### F-1b: a replace-only queue advertised data it could not deliver

`df82ed2`, with `94526ac` applying the same containment to the register family.

`o_read_ready` did not test the head for the max-priority placeholder, so a queue that had booted physically full and logically empty advertised a read that would return a reserved value. The gate implements the containment decided for F-1 across the library. It remains under `if (!ENQ_ENA)` deliberately: an unconditional comparator would add area to five enqueue-capable builds where it can never fire, and would move the published synthesis numbers this library exists to compare.

### 2.4 `bram_tree`

The enqueue-capable BRAM tree, and the module with the most findings. It maintains two independent occupancy mechanisms: a `queue_size` register, which drives the ready ports, and per-node `capacity` fields, which steer where the descent places elements. That redundancy is the reason its final defect was invisible at the interface.

The findings are given in the order they were fixed, because each one exposed the next.

#### F-28: the ready ports depended on the request, so the proof was vacuous

`81a78bb`.

```verilog
assign idle_and_no_new_request = (state == IDLE) && !(i_read || i_wrt);
assign o_write_ready = (queue_size != QUEUE_SIZE) && idle_and_no_new_request;
assign o_read_ready  = (queue_size != 0)           && idle_and_no_new_request;
```

Asserting any command drove both ready signals low in the same cycle. Supplied to the specification's `settled` decode and its no-command-while-busy assumption, this reads as "if a command is issued then no command is issued". The tool therefore issued none. The design never left `IDLE`, and all nine assertions proved over a queue that performs no operations.

No assertion fired. The cover set was the only detector: fifteen of twenty covers were unreachable, including all three command covers and the preconditions of every ordering property. Loosening the cover rule in response would have produced nine vacuous proofs under a green assertion table.

The testbench could not have caught this, because the ready signals and the polling protocol were introduced in the same commit. The testbench polls on the negedge with commands cleared, so it samples a ready only in cycles where the offending term evaluates to 1, and it never holds a request valid while waiting for ready, which is the one protocol this design could not serve. Closed at `9d61bc3`, which drives the DUT from a conventional hold-until-ready master.

Removing the term is behaviour-neutral by inspection, since the acceptance path branches on state and on the raw command bits and never reads the ready outputs. This was confirmed in simulation at `QUEUE_SIZE` 7 and 15. One measured figure moved: minimum enqueue and replace latency fell from 2 cycles to 1. That figure was a measurement artifact of the defect, not a change in the design.

#### F-29: reset never restored the node memory

`b4872a5`.

The F-25 defect on this module, where it is more serious, because `bram_tree`'s `capacity` fields carry the free-space accounting the descent depends on. Every arm of `ENQUEUE_COMPARE_CHILD` requires a child capacity greater than zero and there is no terminal `else`, so a stale zero capacity leaves the walk in a self-loop, which is what the progress property had been reporting.

The fix is a sweep, with one complication the pipelined module does not have: the fill value is not constant, since node *i* roots a subtree of `((NODES_NEEDED+1) >> level(i)) - 1` and `level(i)` is `floor(log2(i+1))`. Rather than compute a logarithm per node, the sweep carries the level and steps it at the subtree boundaries:

```verilog
assign fill_cap = ADDRESS_WIDTH'(((NODES_NEEDED + 1) >> fill_level) - 1);
...
if ((fill_cnt + 1'b1) == fill_bound[ADDRESS_WIDTH-1:0]) begin
  fill_level <= fill_level + 1'b1;
  fill_bound <= (fill_bound << 1) + 'd1;
end
```

Fixing it approximately doubled every remaining counterexample depth, which indicates that a short route to failure was closed rather than that the remaining defects were fixed, and is why the two guards below were still required. Simulation could not reach this defect at all; reverting the fix now causes the suite to hang on the second reset.

#### F-30: a dequeue on an empty queue was not inert

`7eb9f2c`.

```verilog
end else if (!i_wrt && i_read) begin // --- DEQUEUE ---
//                            ^^^ no occupancy guard
```

The `IDLE` arm relied entirely on the caller honouring `o_read_ready`. A dequeue on an empty queue ran the full compare-root walk and drove `next_queue_size` to `queue_size - 1`, underflowing the counter. It also overflowed the root capacity, since the dequeue arm computes `capacity + 1` and, on an empty queue at `QUEUE_SIZE=7`, 7+1 truncates to 0.

```verilog
end else if (!i_wrt && i_read && (queue_size != 0)) begin   // --- DEQUEUE ---
```

The guard lets the command fall through the chain with state and counter unchanged, which is the inertness principle established by F-8 on `systolic_array`. The change is byte-identical in simulation at both geometries, because every dequeue the testbench issued was gated on the ready signal it was intended to test. Closed at `7d5a9d3` and `fdb7003`.

#### F-31: an enqueue on a full queue was not inert

`42133b6`.

The mirror of F-30 on the enqueue arm, with the same repair:

```verilog
if (i_wrt && !i_read && (queue_size != QUEUE_SIZE)) begin   // --- ENQUEUE ---
```

The 32-cycle counterexample depth is itself the attribution: the violation is not expressible until the queue is actually full.

The fix cleared eight counterexamples simultaneously: its own, plus `a_progress`, both occupancy agreements, `a_no_loss`, and both head properties. The ordering and conservation failures were therefore downstream of unguarded command acceptance rather than independent ordering defects. This retires an earlier claim in this effort that the walk had a separate non-termination defect. The terminal `else` that code inspection had proposed for `ENQUEUE_COMPARE_CHILD` was not required, and would have been unreachable code obscuring the actual causes.

The testbench approaches this defect and stops, printing `"Queue full, skipping enqueue"`.

#### F-32: replace-on-empty corrupted the root capacity, and no port could observe it

`64edf79`.

```verilog
next.capacity = (empty) ? top_level.capacity + 1 : top_level.capacity;
```

A replace on an empty queue inserts an element, so free space must decrease, which is what the enqueue arm assigns for the identical case. The assignment is wrong in two respects: the direction is the dequeue arm's, and the result overflows, because `capacity` equals `QUEUE_SIZE` on an empty queue and the field is `ADDRESS_WIDTH` bits wide, so 7+1 truncates to 0.

The entire portable specification proved green with this defect present. All ten interface-level assertions covering ordering, occupancy, conservation, progress and the reset contract pass while the root's free-space count reads 0 in a queue holding one element. The ready ports are unaffected because `queue_size` is maintained separately and is what drives them. Measured on the source, six branch conditions read a capacity and all six read it from RAM; none reads the corrupted root copy. The value is propagated but never tested.

It was found by `a_root_capacity_agrees`, a white-box invariant written specifically to decide the question. The sweep confirms that property remains the only detector: reverting the fix at HEAD gives ten assertions proven, one counterexample, and all twenty-three covers reachable. This is measured evidence that the portable specification cannot observe this class of defect, and therefore that white-box addenda are the only means by which internal invariants are checked at all.

Simulation could not observe it either, because every check compared `o_data` against the reference head, and a differently shaped but still valid heap is indistinguishable from the head alone. Closed at `41749ed`, which checks the heap interior through the shim hook; reverting this fix now fails in simulation by name.

One process note. This fix was committed once before, on a superseded branch, justified only by reading the source, with no property and no failing run. The reading was correct, which is the difficulty: it produced a correct result by a method that had no means of detecting an incorrect one. A fix whose sole justification is that the code appears wrong is not a finding.

What is not claimed is that the defect was harmless. The proof establishes no interface-observable violation at `QUEUE_SIZE=7, DATA_WIDTH=2`. A wrong capacity steering the descent in a deeper tree is the shape that strands the walk, and a run at `QUEUE_SIZE=15` remains an open question.

## 3. Changes to the simulation suite

The proofs found defects the simulation suite could not, and in most cases could not have. `bram_tree` is the clearest case: six defects were fixed under proof, and five of them produced byte-identical simulation output at both `QUEUE_SIZE` 7 and 15. Not "the tests still passed", but output a diff cannot distinguish. The sixth changed one line, the total runtime, by five clock periods.

The reason is a single property of the suite as it stood. Every command was gated on the DUT's own ready signals, the reference model derived its occupancy from those same signals, reset happened once before any stimulus, and the only value ever checked was the head. Each is a reasonable choice individually. Together they define a region the suite could not enter, and five `bram_tree` defects were inside it.

Eight commits address this. Each is traceable to a specific defect, and five of the eight were verified to go red against that defect by reverting its fix and observing the check name it. All thirteen simulation configurations pass after each commit, and every check reaches `$fatal` through `error_count`, so `run_sim.sh` reports it.

| commit | change | motivating defect | verified to catch it |
|---|---|---|---|
| `a19e95e` | assert reset during operation, not only before it | F-25, F-29 | yes, settle timeout on the second reset |
| `7d5a9d3` | issue commands the DUT says it will not accept | F-30, F-31 | yes, by name |
| `fdb7003` | make the reference model independent of the DUT | F-2, F-7, F-22 | yes, by name |
| `cfec1ae` | compare whole drained sequences, not the head alone | F-32 class | no unique catch on the register trees |
| `a24f82f` | narrow payload alphabet to force ties | tie density | no unique catch, by construction |
| `9d61bc3` | drive the DUT from a conventional ready/valid master | F-28 | yes, in both directions |
| `41749ed` | check the BRAM interiors, which no port can observe | F-32 | yes, naming the truncation |
| `ea60a6a` | trip on X reaching the sift comparator inputs | F-23 | not a defect detector; see section 4 |

Four of these need justification beyond the table.

Making the reference model independent of the DUT (`fdb7003`) inverts a dependency rather than adding a check. The model previously gated its own updates on the DUT's readies, so "refuses work it should accept" was structurally uncatchable: the model agreed with whatever the DUT did. It now maintains its own occupancy and asserts the readies against it. `CAPACITY` is parameterised the way the formal specification parameterises it, because it is not `QUEUE_SIZE` everywhere: `systolic_array` holds `QUEUE_SIZE-2` under F-9, and `bram_tree_pipelined` never advertises full at all.

Issuing commands the DUT refuses (`7d5a9d3`) asserts that nothing happens. That is the correct shape: a refused command doing nothing is the contract established by F-8, and a refused command doing something is the defect.

Two checks are honest about their limits, and the commit messages say so rather than implying a catch they did not make. The heap-invariant check (`cfec1ae`) could not be shown to catch anything the port checks miss on `register_tree`; two injections were tried and both were absorbed. Its demonstrated case is F-32, whose interior lives in BRAM, and that follow-up is `41749ed`. The class therefore has a demonstrated catch while `register_tree`'s instance of it does not. The narrow alphabet (`a24f82f`) has no uniquely catchable injection, because payloads carry no tag, so equal values are interchangeable and swapping on equality is unobservable. It earns its place by running the comparators at roughly 97% tie density against the previous 13%, which is the density the proofs run at, rather than by a catch.

No new RTL defect was found by any of these eight. That is the expected outcome rather than a disappointment: every defect in this class had already been found and fixed under proof. The changes close the gap going forward, on a suite that runs on every push while the proof tool does not.

## 4. Retracted findings

Three findings reported as defects did not survive measurement. In two cases the fix is retained anyway, and the reasoning for retaining it is given, because a retained fix in a library whose purpose is comparing area is not free.

### F-17: `bram_tree_pipelined`'s reported defects were harness artifacts

Retracted in full.

This finding claimed the module broke its heap invariant, overflowed its counter, and did not conserve its contents. None of that was true. Six of the seven claims were consequences of F-21, the multiply-driven RAM model, which allowed the tool to choose the memory contents. The seventh was a sampling window: `quiesced` was defined over three cycles of `sift_done`, which resets high, so the window opened two cycles after reset, inside the placeholder sweep, with the memory half written. Retiring coverage hole CH-6 is what exposed it, because the contents then powered up arbitrary by design.

The evidence was present and was not read. `VDB-1000` and `IMDS005` named the multiply-driven array on every run from the first. Separately, the counterexample depth for the conservation property collapsed from 160 cycles to one when an assumption changed, and a one-cycle counterexample on a property about accumulated state is almost always the property rather than the design.

The entry is retained because the way it went wrong is the most transferable result in this document. The triage procedure it produced is in [`README.md`](README.md), since it is guidance for the next contributor rather than a result about this library.

### F-23: out-of-range accesses in the sift walk

Retracted as a defect. The fix, `5b7dff4`, is retained.

Ten `VERI-9005` sites were reported at elaboration, six of them guarded by the fix. The reported defect was that the sift walk reads child indices outside the array at the deepest level.

The accesses are real and the retraction is measured, not argued. Reverting `5b7dff4` at HEAD leaves the formal run fully green at 20 assertions proven, 0 counterexamples and 35 covers reachable. It also leaves the simulation suite green, with byte-identical cycle histograms. Instrumented identically at `QUEUE_SIZE=15`, the deepest level is entered 1452 times in both builds, and X reaches the comparator inputs 0 times with the guards and 2159 times without them. The condition is reachable, heavily exercised, and genuinely injects X, and both halves of the suite are green regardless, because X never reaches `o_data` and every check observed the port.

The RTL explains why. An override at the end of the same combinational arm, predating `5b7dff4`, kills every tainted path before it can be committed:

```verilog
if (parent_lvl == TREE_DEPTH - 1) begin  // if we are at the last level
  next_parent_lvl = 'd0;
  next_parent_idx = 'd0;
  next_we_a[parent_lvl] = 1'b0;
  next_we_b[parent_lvl] = 1'b0;
end
```

The walk terminates by design, not by accident.

Synthesis agrees, where there is no X at all. Vivado 2025.1, `xcau25p-ffvb676-1-e`, out of context, at `QUEUE_SIZE=15, DATA_WIDTH=16`: 1272 LUTs with the guards against 1259 without, 789 flip-flops in both, the same CARRY8 and RAM usage, and the same warnings, with no out-of-range or critical warnings in either. The one falsifiable hazard, write aliasing, would require more decode logic, and the unguarded build has less logic with identical sequential state, which points away from it. This is convergent evidence rather than a proven equivalence: the netlists differ and no logical equivalence checker was available.

The guards are retained as hardening, and they cost 13 LUTs in a library that exists to compare area. That cost is recorded rather than absorbed. `tools/mutations/SWEEP.tsv` carries this as an `expect=none` row, which pins the measured green: a future change that begins detecting it will report the row as changed and the retraction will be revisited.

The remaining bound question is settled rather than open. Two `level_1[parent_idx]` sites are in range only by an invariant the walk maintains rather than by construction, since `level_1` has two entries and `parent_idx` is three bits wide. `a_level1_index_in_range` in `formal/spec/hwpq_bram_aux.sv` asserts it directly and proves. The cover `c_deepest_level_walked` separately establishes that the deepest level really is reached, which is what makes the guards a decision about reachable cycles rather than a hypothetical.

The X monitor added at `ea60a6a` is a tripwire on the deepest-level override, not a defect detector, and its comment says so.

### F-26: the free-running sift walk during the reset fill

Retracted as a defect. The fix, `07dff2b`, is retained as a defensive change.

The claim was that the sift walk advances out of `IDLE` unconditionally, so during the reset fill it drives the comparator from memory read back mid-sweep and can write that result over the fill on the cycle `filling` drops.

Reverting the fix at HEAD gives 20 assertions proven, 0 counterexamples and 35 covers reachable, byte-identical to unmodified HEAD. The precondition is not merely unexercised. The three properties quoted in this section were written against the reverted design to decide the question and are deliberately not in the shipped spec; they will not be found in `formal/spec/`. On the reverted design both of these are reachable in two cycles:

```verilog
c_walk_runs_during_fill : filling && state != IDLE
c_walk_dirties_fill     : filling && state != IDLE && comp_parent_out != '1
```

The walk really does free-run during the sweep, and the comparator really does emit non-placeholder values while it runs. Nothing dirty survives, however. On that same reverted design this proves:

```verilog
$fell(filling) |-> fill_intact && level_0 == '1 && level_1[0] == '1 && level_1[1] == '1
```

The reason the BRAM was never at risk is that `d84465e`, the preceding commit rather than this fix, already drives the address, data and write-enable lines on every BRAM level every cycle while `filling`. The walk cannot reach the memory. What `07dff2b` protects is the two register levels, which the sweep does not write, and those are demonstrably correct at the end of the fill without it.

Three mechanistic hypotheses were proposed and all three were falsified. No fourth is offered, which is the point: the conclusion is what the runs establish, not a mechanism. At the proven geometry of `QUEUE_SIZE=7, DATA_WIDTH=2` with one BRAM level, this is not a reachable defect. Larger geometries are unproven, since `QUEUE_SIZE=15` does not converge.

One repair should not be attempted:

```verilog
assert property (filling |-> state == IDLE);   // do NOT add this
```

It does redden on the revert, but because the transition changed rather than because anything is corrupted. That is mutation detection in the form of verification, and it would manufacture coverage for a defect that is not observable.

### F-24: a retraction candidate, not yet retracted

The evidence is in section 2.3. The sweep reverts `e0cec3a` and nothing reddens, `a_no_placeholder_at_capacity` proves, and re-running at the original commit with a sound RAM model shows both formerly failing properties proving while the relevant cover still reaches. The original counterexample was an F-21 artifact.

It is listed as a candidate rather than retracted because the disposition has not been decided. The guard is retained in either case, on the same reasoning as F-23.

## 5. Open items

Nothing below blocks the results in sections 2 and 3. Each is a stated limit or a known gap.

Assumptions currently in force, each of which is a region the proofs do not cover:

- CH-1, reserved values. `i_data` in `{'0, '1}` is assumed away as a scoping decision. Behaviour when those values are driven is characterised in appendix A and is outside the library's supported input range.
- CH-2, no command while busy. Any defect requiring a command to arrive mid-operation is unreachable while this holds. Each module has a second, ungated run, which is how the assumption is checked rather than trusted.
- CH-3, parametric generality. The proofs hold at the geometries listed in section 6 and at no others.
- CH-4, fill before read. The replace-only builds are constrained to fill the queue before reading from it. This is the disposition of F-1 rather than a temporary scope, and all four replace-only register modules have their ungated run.

CH-5 is closed, by F-7. CH-6 is retired on both BRAM modules, and is the only hole this effort closed by fixing the design rather than by scoping a property: the reset fill sequencers added under F-25 and F-29 establish the memory contents from arbitrary power-up state, so the assumption that had pinned them stopped being load-bearing and was deleted. Both BRAM modules now prove with their memories entirely free, which is stronger than the assumption ever permitted.

Remaining gaps:

- F-33. The synthesis sweep script reads a path that has not existed since `3c72b09`, finds no RTL, and continues without reporting it. Every published area number therefore predates seventeen RTL fixes. Not repaired; deliberately out of scope for this work.
- F-18. Both BRAM modules are proven at `DATA_WIDTH=2`. `bram_tree_pipelined` at width 3 did not converge in 3600 seconds once the RAM model was sound. This is a standing limit on what those proofs claim.
- `bram_tree` at `QUEUE_SIZE=15` does not converge, which leaves the deeper-tree consequence of F-32 unresolved.
- F-13. Expected-counterexample matching in `--ungated` runs is by property name, so a changed defect reads as an unchanged one. Closed as discipline rather than repaired in the tooling.
- F-21 has a third copy of the multiply-driven RAM model in `hybrid_tree`, which is out of scope and will need it before it can be verified.

## 6. Reproducing these results, and their limits

Every claim in section 2 is re-checkable by one of two mechanisms, both driven from `regress.sh` and both reading a tracked manifest.

`regress.sh --sweep` reads [`tools/mutations/SWEEP.tsv`](tools/mutations/SWEEP.tsv). Each row reverts one fix, or applies a patch where a revert is impossible, and requires a named detector to fire: a specific counterexample, an unreachable cover, an elaboration failure with a given code and count, a harness abort, non-convergence, or nothing at all. The last of these is not an absent result. An `expect=none` row pins a measured green, so a future change that begins detecting the mutation is reported. Two of the three such rows, F-23 and F-26, are retracted findings, which is what a correct retraction looks like from inside the sweep; the third, F-24, is a retraction candidate.

`regress.sh --baseline` reads [`tools/baseline/MANIFEST.tsv`](tools/baseline/MANIFEST.tsv). Each row checks out the pre-verification RTL at `af089e5`, overlays the current harness, cherry-picks only the commits named in the row, and runs. This is the complement of the sweep: the sweep re-runs because the design moves, the baseline because the instrument does.

The two manifests carry aligned column positions deliberately, so that one driver provides dispatch, control runs, drift warnings and verdict parsing for both rather than growing a second, slightly different copy of each.

Limits on what any of this claims:

- The proofs are exhaustive at one geometry each and say nothing about others. Those geometries are `QUEUE_SIZE=4, DATA_WIDTH=3` for the `register_array` family; `QUEUE_SIZE=7, DATA_WIDTH=3` for the `register_tree` family; `QUEUE_SIZE=8, DATA_WIDTH=3` for `systolic_array`; and `QUEUE_SIZE=7, DATA_WIDTH=2` for both BRAM modules.
- Formal analysis here is two-state. It cannot model X propagation, which is why the F-23 question had to be settled by simulation and synthesis instead.
- The claims are relative to the shared specification and its addenda. F-32 is the measured demonstration that this matters: a module can satisfy the entire portable interface specification while its internal accounting is wrong.
- The baseline measures the design as it stood when verification began, once a common interface existed, and not the design as originally written. The uniform six-port interface arrived at `e7c20ad` and is part of this work.

## Appendix A. Reserved-value behaviour

Recorded so the knowledge is not lost. All of this was reproduced in simulation. None of it is on the roadmap: it is behaviour outside the library's supported input range, per CH-1, and the specification assumes those values away.

`systolic_array` wedges permanently on a payload of 0. Both readies are gated on `o_data != MIN_VALUE`, and `MIN_VALUE` is 0. With a 0 at the head of a non-empty queue both readies go low and no command can be accepted, including the dequeue that would clear it. Reproduced from reset in five commands and held for 20,000 cycles. The RTL comment already documents the restriction.

The size counter is unbounded on a replace of all-ones in replace-only mode. The all-ones arm in the register family has no fullness guard, unlike the enqueue and dequeue arms. Reproduced on all four register modules: `size` wraps, and the queue then reports empty while every slot holds data. This is the same code shape as F-24 on `bram_tree_pipelined`, where it is a genuine defect because the module reaches the state unaided; here it requires the caller to drive a reserved value.

A payload of 0 is not a problem for the register modules. Directed testing shows no divergence, because `'0` is the minimum, so a stored zero and a padding zero are interchangeable. Suite failures under zero injection come from the testbench's own reference model desynchronising over the question of what a replace with a zero payload means, not from the RTL.

If the library later commits to supporting these values, the repair for the first is a validity bit rather than a reserved value, and for the second a fullness guard.
