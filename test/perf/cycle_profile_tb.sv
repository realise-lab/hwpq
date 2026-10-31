// Cycle profiler for one queue on the uniform interface; cycle_profile.sh builds and runs it.
//   mix (default)  fill to half capacity, then M ops drawn evenly from enqueue, dequeue and
//                  replace; prints the cost of each op type and of all ops. A replace-only
//                  build cannot refill after a dequeue, so its mix is M replaces at full.
//   +stream        fill from empty to capacity, CAP replaces at full, then drain to empty;
//                  prints the cost of each phase and checks the drain comes out in order.
// An op's cost is the cycles it is presented, counting the cycle it is accepted in. The master
// holds each op until its ready is high and presents the next in the following cycle.
// Ready per op: enqueue o_write_ready, dequeue o_read_ready, replace o_read_ready, or
// o_write_ready || o_read_ready in a replace-only build. A replace-only build gets no enqueue and
// fills by replacing its reset fill. Only its stream gets a replace when empty.
//
// Defines: DUT=<module>; DUT_ENQ_ENA if it takes ENQ_ENA; DUT_NO_PARAMS if sized by defines.
// Plusargs: +stream; +mono=1 / +mono=-1, each value >= / <= the last, in steps of 0 to STEP;
// +seed=<n>.
`timescale 1ns/1ps
module cycle_profile_tb;
  parameter int QS   = 15;     // QUEUE_SIZE
  parameter int W    = 16;     // DATA_WIDTH
  parameter bit ENQ  = 1;      // ENQ_ENA
  parameter int CAP  = QS;     // elements the DUT holds
  parameter int M    = 12000;  // ops in the mix
  parameter int STEP = 3;
  localparam int STUCK = 1000;  // cycles one op may wait before the run fails

  logic         i_CLK = 0, i_RSTn = 0, i_wrt = 0, i_read = 0;
  logic [W-1:0] i_data = '0;
  logic         o_write_ready, o_read_ready;
  logic [W-1:0] o_data;
  always #5 i_CLK = ~i_CLK;

`ifdef DUT_ENQ_ENA
  `DUT #(.ENQ_ENA(ENQ), .QUEUE_SIZE(QS), .DATA_WIDTH(W)) dut (.*);
`elsif DUT_NO_PARAMS
  `DUT dut (.*);
`else
  `DUT #(.QUEUE_SIZE(QS), .DATA_WIDTH(W)) dut (.*);
`endif

  typedef enum int {ENQUEUE, DEQUEUE, REPLACE} op_t;
  int held = 0;                      // elements in the queue
  int placeholders = ENQ ? 0 : CAP;  // reset fill of a replace-only build, evicted first
  int mono = 0;
  logic [W-1:0] popped;              // head taken by the last dequeue or replace

  // Payloads avoid the reserved '0 and '1.
  localparam logic [W-1:0] TOP = {W{1'b1}} - 1'b1;
  logic [W-1:0] last = {1'b1, {(W - 1){1'b0}}};
  function automatic logic [W-1:0] next_value();
    int step = $urandom_range(0, STEP);
    if (mono > 0)      last = (last > TOP - step) ? TOP : last + step;
    else if (mono < 0) last = (last < 1 + step) ? 1 : last - step;
    else begin
      last = {4{$urandom}};
      if (last == 0 || last > TOP) last = 1;
    end
    return last;
  endfunction

  function automatic bit ready(op_t op);
    case (op)
      ENQUEUE: return o_write_ready;
      DEQUEUE: return o_read_ready;
      default: return ENQ ? o_read_ready : o_write_ready || o_read_ready;
    endcase
  endfunction

  // Starts at a negedge; returns at the negedge after the DUT accepts the op.
  task automatic run_op(op_t op, output int cycles);
    i_wrt  = op != DEQUEUE;
    i_read = op != ENQUEUE;
    i_data = i_wrt ? next_value() : '0;
    cycles = 1;
    #1;  // a ready may depend on the command just driven
    while (!ready(op)) begin
      if (cycles == STUCK) $fatal(1, "%s not accepted in %0d cycles", op.name(), STUCK);
      @(negedge i_CLK);
      cycles++;
      #1;
    end
    popped = o_data;
    @(negedge i_CLK);
    i_wrt  = 0;
    i_read = 0;
    case (op)
      ENQUEUE: held++;
      DEQUEUE: held--;
      REPLACE: if (placeholders > 0) begin
        placeholders--;
        held++;
      end else if (held == 0) held++;
    endcase
  endtask

  // Cost totals per slot: op type in the mix, phase in the stream.
  string  names [3];
  longint total [3];
  int     count [3], worst [3];
  task automatic measure(int slot, op_t op);
    int c;
    run_op(op, c);
    total[slot] += c;
    count[slot]++;
    if (c > worst[slot]) worst[slot] = c;
  endtask

  // Any command, evenly; at a bound, the one that can still go. Replace-only: replace.
  function automatic op_t pick();
    op_t op = ENQ ? op_t'($urandom_range(0, 2)) : REPLACE;
    if (held == 0) return ENQ ? ENQUEUE : REPLACE;
    if (op == ENQUEUE && held == CAP) return REPLACE;
    return op;
  endfunction

  initial begin
    bit   stream;
    op_t  fill, op;
    int   seed, c;
    logic [W-1:0] prev;
    stream = $test$plusargs("stream");
    fill = ENQ ? ENQUEUE : REPLACE;
    if ($value$plusargs("seed=%d", seed)) void'($urandom(seed));
    void'($value$plusargs("mono=%d", mono));

    repeat (2) @(posedge i_CLK);
    @(negedge i_CLK) i_RSTn = 1;
    do @(negedge i_CLK); while (!(o_write_ready || o_read_ready));  // post-reset initialisation

    if (!stream) begin
      names[0] = "enq"; names[1] = "deq"; names[2] = "rep";
      repeat (ENQ ? CAP / 2 : CAP) run_op(fill, c);
      repeat (M) begin
        op = pick();
        measure(int'(op), op);
      end
    end else begin
      names[0] = "fill"; names[1] = "rep"; names[2] = "drain";
      repeat (CAP) measure(0, fill);
      repeat (CAP) measure(1, REPLACE);
      prev = '1;
      repeat (CAP) begin
        measure(2, DEQUEUE);
        if (popped == 0 || popped > prev) $fatal(1, "drain gave %0d after %0d", popped, prev);
        prev = popped;
      end
    end

    $write("RESULT");
    if (!stream) $write(" all=%.3f", real'(total[0] + total[1] + total[2]) / M);
    for (int s = 0; s < 3; s++)
      if (count[s]) $write(" %s=%.3f %s_max=%0d", names[s], real'(total[s]) / count[s],
                           names[s], worst[s]);
    $write("\n");
    $finish;
  end
endmodule
