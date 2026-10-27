// TITAN-X TB harness macros — include INSIDE your TB module body:
//     `include "tb_macros.vh"
// Requires the TB to declare:  reg clk; reg rst_n;  (driven by TB_HARNESS)
//
// Contract with scripts/run_regress.py:
//   Every path ends printing exactly one "REGRESS_RESULT: PASS|FAIL" line.

`ifndef TITANX_TB_MACROS
`define TITANX_TB_MACROS

// Clock + reset + global watchdog. TIMEOUT_NS is wall sim-time.
`define TB_HARNESS(TIMEOUT_NS)                                          \
    initial begin clk = 1'b0; forever #5 clk = ~clk; end               \
    initial begin                                                      \
        rst_n = 1'b0;                                                  \
        repeat (8) @(posedge clk);                                     \
        rst_n = 1'b1;                                                  \
    end                                                                \
    initial begin                                                      \
        #(TIMEOUT_NS);                                                 \
        $display("WATCHDOG: timeout at %0t — forcing FAIL", $realtime);\
        $display("REGRESS_RESULT: FAIL");                              \
        $finish;                                                       \
    end

// Scoreboard state
`define TB_SCOREBOARD                                                   \
    integer tb_errors = 0;                                              \
    integer tb_checks = 0;

`define EXPECT_EQ(ACT, EXP, LABEL)                                      \
    begin                                                              \
        tb_checks = tb_checks + 1;                                     \
        if ((ACT) !== (EXP)) begin                                     \
            tb_errors = tb_errors + 1;                                 \
            $display("[FAIL] %0t %s: got %h expected %h (%m)",         \
                     $time, LABEL, ACT, EXP);                          \
        end                                                            \
    end

`define EXPECT_NE(ACT, EXP, LABEL)                                      \
    begin                                                              \
        tb_checks = tb_checks + 1;                                     \
        if ((ACT) === (EXP)) begin                                     \
            tb_errors = tb_errors + 1;                                 \
            $display("[FAIL] %0t %s: unexpectedly equals %h (%m)",     \
                     $time, LABEL, ACT);                               \
        end                                                            \
    end

// Any X/Z bits in the given value fails the check
`define EXPECT_KNOWN(VAL, WIDTH, LABEL)                                 \
    begin                                                              \
        tb_checks = tb_checks + 1;                                     \
        if (^((VAL) ^ (VAL)) !== 1'b0) begin                           \
            tb_errors = tb_errors + 1;                                 \
            $display("[FAIL] %0t %s: X/Z detected in %h (%m)",         \
                     $time, LABEL, VAL);                               \
        end                                                            \
    end

`define EXPECT_TRUE(COND, LABEL)                                        \
    begin                                                              \
        tb_checks = tb_checks + 1;                                     \
        if (!(COND)) begin                                             \
            tb_errors = tb_errors + 1;                                 \
            $display("[FAIL] %0t %s: condition false (%m)", $time, LABEL); \
        end                                                            \
    end

// Mandatory closer. NAME is a short string identifying the bench.
`define TB_REPORT(NAME)                                                 \
    begin                                                              \
        $display("------------------------------------------------");  \
        $display("%s: %0d checks, %0d errors", NAME, tb_checks, tb_errors); \
        if (tb_errors == 0)                                            \
            $display("REGRESS_RESULT: PASS");                          \
        else                                                           \
            $display("REGRESS_RESULT: FAIL");                          \
        $finish;                                                       \
    end

`endif // TITANX_TB_MACROS
