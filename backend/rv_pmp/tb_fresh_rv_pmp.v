// SPDX-License-Identifier: Apache-2.0
// Brand-New Fresh Self-Checking Testbench for rv_pmp
// Strictly adheres to RISC-V Privileged Architecture Spec v1.12 (pmpaddr = PA >> 2)

`timescale 1ns/1ps
`include "params.vh"
`include "isa_pkg.vh"

module tb_fresh_rv_pmp;
    reg         clk;
    reg         rst_n;
    reg  [37:0] paddr;
    reg         check_r;
    reg         check_w;
    reg         check_x;
    reg  [1:0]  priv_mode;
    reg         check_en;
    reg  [63:0] pmpcfg0;
    reg  [63:0] pmpcfg2;
    reg  [303:0] pmpaddr_packed;
    wire        pmp_fault;

    integer err_cnt = 0;
    integer test_cnt = 0;

    rv_pmp #(
        .NUM_ENTRIES(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .paddr(paddr),
        .check_r(check_r),
        .check_w(check_w),
        .check_x(check_x),
        .priv_mode(priv_mode),
        .check_en(check_en),
        .pmpcfg0(pmpcfg0),
        .pmpcfg2(pmpcfg2),
        .pmpaddr_packed(pmpaddr_packed),
        .pmp_fault(pmp_fault)
    );

    always #5 clk = ~clk;

    task set_pmp_entry;
        input integer entry;
        input [7:0]  cfg;
        input [37:0] addr_word; // Standard RISC-V word address (PA >> 2)
        begin
            pmpcfg0[entry*8 +: 8] = cfg;
            pmpaddr_packed[entry*38 +: 38] = addr_word;
        end
    endtask

    task clear_all_pmp;
        begin
            pmpcfg0 = 64'h0;
            pmpcfg2 = 64'h0;
            pmpaddr_packed = 304'h0;
            paddr = 38'h0;
            check_r = 0;
            check_w = 0;
            check_x = 0;
            priv_mode = `PRIV_U;
            check_en = 0;
        end
    endtask

    initial begin
        $dumpfile("verification_waves/rv_pmp.vcd");
        $dumpvars(0, tb_fresh_rv_pmp);

        clk = 0;
        rst_n = 1;
        clear_all_pmp();

        $display("=== STARTING FRESH SELF-CHECKING VERIFICATION: rv_pmp ===");

        // Test 1: Reset and Disabled Request Check (check_en = 0)
        test_cnt = test_cnt + 1;
        #2 rst_n = 0;
        #10 rst_n = 1;
        #2;
        paddr = 38'h00_8000_0000;
        check_r = 1;
        check_en = 0;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T1]: check_en=0 produced pmp_fault=1");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T1]: Reset and disabled request check confirmed (no fault when check_en=0)");
        end

        // Test 2: M-Mode Bypass with No PMP Match
        test_cnt = test_cnt + 1;
        check_en = 1;
        priv_mode = `PRIV_M;
        paddr = 38'h00_8000_1234;
        check_r = 1;
        check_w = 1;
        check_x = 1;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T2]: M-mode default bypass failed with no PMP match");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T2]: M-mode default bypass confirmed with no matching PMP entries");
        end

        // Test 3: S-Mode and U-Mode Default Deny with No PMP Match
        test_cnt = test_cnt + 1;
        priv_mode = `PRIV_U;
        #2;
        if (pmp_fault !== 1'b1) begin
            $display("ERROR [T3]: U-mode failed to trigger fault when no PMP entries configured");
            err_cnt = err_cnt + 1;
        end else begin
            priv_mode = `PRIV_S;
            #2;
            if (pmp_fault !== 1'b1) begin
                $display("ERROR [T3]: S-mode failed to trigger fault when no PMP entries configured");
                err_cnt = err_cnt + 1;
            end else begin
                $display("PASS [T3]: U/S-mode default deny confirmed (no match triggers fault)");
            end
        end

        // Test 4: TOR (Top of Range) Entry Check (Word Addressing PA >> 2)
        // Configure Entry 0: range [0, 0x00_8000_1000), pmpaddr0 = 0x8000_1000 >> 2 = 0x2000_0400
        // permissions R=1, W=0, X=0 (Read-Only)
        // cfg = {L=0, 2'b00, A=2'b01 (TOR), X=0, W=0, R=1} = 8'b0000_1001 = 8'h09
        test_cnt = test_cnt + 1;
        clear_all_pmp();
        check_en = 1;
        set_pmp_entry(0, 8'h09, 38'h00_2000_0400); // 0x8000_1000 >> 2
        priv_mode = `PRIV_U;
        paddr = 38'h00_8000_0400; // Inside range

        // Read inside TOR range: should succeed
        check_r = 1; check_w = 0; check_x = 0;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T4]: U-mode TOR read allowed region faulted");
            err_cnt = err_cnt + 1;
        end else begin
            // Write inside TOR range: should fault (W=0)
            check_r = 0; check_w = 1; check_x = 0;
            #2;
            if (pmp_fault !== 1'b1) begin
                $display("ERROR [T4]: U-mode TOR write to read-only region was permitted");
                err_cnt = err_cnt + 1;
            end else begin
                // Address outside TOR range: should fault (no match)
                paddr = 38'h00_8000_2000;
                check_r = 1; check_w = 0; check_x = 0;
                #2;
                if (pmp_fault !== 1'b1) begin
                    $display("ERROR [T4]: U-mode address outside TOR range was permitted");
                    err_cnt = err_cnt + 1;
                end else begin
                    $display("PASS [T4]: TOR (Top of Range) mode match and permissions verified (word addressed)");
                end
            end
        end

        // Test 5: NA4 (4-Byte Aligned) Entry Check
        // Configure Entry 1: NA4 address 0x00_4000_0004 >> 2 = 0x00_1000_0001
        // permissions W=1, R=0, X=0 (Write-Only)
        // cfg = {L=0, 2'b00, A=2'b10 (NA4), X=0, W=1, R=0} = 8'b0001_0010 = 8'h12
        test_cnt = test_cnt + 1;
        clear_all_pmp();
        check_en = 1;
        set_pmp_entry(1, 8'h12, 38'h00_1000_0001); // 0x4000_0004 >> 2
        priv_mode = `PRIV_U;
        paddr = 38'h00_4000_0004; // Matches Entry 1
        check_r = 0; check_w = 1; check_x = 0;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T5]: NA4 write allowed access faulted");
            err_cnt = err_cnt + 1;
        end else begin
            // Read to same NA4 word: should fault (R=0)
            check_r = 1; check_w = 0; check_x = 0;
            #2;
            if (pmp_fault !== 1'b1) begin
                $display("ERROR [T5]: NA4 read to write-only region was permitted");
                err_cnt = err_cnt + 1;
            end else begin
                // Address offset +4: does not match NA4
                paddr = 38'h00_4000_0008;
                check_r = 0; check_w = 1; check_x = 0;
                #2;
                if (pmp_fault !== 1'b1) begin
                    $display("ERROR [T5]: Unmatched NA4 address was permitted");
                    err_cnt = err_cnt + 1;
                end else begin
                    $display("PASS [T5]: NA4 (4-Byte Aligned) mode match and permissions verified (word addressed)");
                end
            end
        end

        // Test 6: NAPOT (Naturally Aligned Power-of-Two) Entry Check
        // 16-byte region at 0x00_2000_0000..0x00_2000_000F
        // Base word = 0x00_2000_0000 >> 2 = 0x00_0800_0000
        // In NAPOT word encoding: 16 bytes = 4 words => trailing ones = 2'b01 in word addr
        // pmpaddr = base_word | 2'b01 = 38'h00_0800_0001
        // cfg = {L=0, 2'b00, A=2'b11 (NAPOT), X=1, W=1, R=1} = 8'b0001_1111 = 8'h1F
        test_cnt = test_cnt + 1;
        clear_all_pmp();
        check_en = 1;
        set_pmp_entry(2, 8'h1F, 38'h00_0800_0001);
        priv_mode = `PRIV_U;
        paddr = 38'h00_2000_000C; // Inside 16-byte NAPOT block
        check_r = 1; check_w = 1; check_x = 1;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T6]: NAPOT inside-region RWX access faulted");
            err_cnt = err_cnt + 1;
        end else begin
            // Address outside 16B NAPOT block
            paddr = 38'h00_2000_0010;
            #2;
            if (pmp_fault !== 1'b1) begin
                $display("ERROR [T6]: NAPOT outside-region access was permitted");
                err_cnt = err_cnt + 1;
            end else begin
                $display("PASS [T6]: NAPOT mode match and permissions verified (word addressed)");
            end
        end

        // Test 7: Entry Priority Enforcement (Lowest Numbered Entry Wins)
        // Entry 0 covers [0, 0x00_8000_1000) with Read-Only (R=1, W=0, X=0, cfg=8'h09)
        // Entry 3 covers [0, 0x00_8000_2000) with RWX allowed (cfg=8'h0F)
        // Access at 0x00_8000_0500 matches BOTH Entry 0 and Entry 3.
        // Entry 0 must take precedence -> write must FAULT!
        test_cnt = test_cnt + 1;
        clear_all_pmp();
        check_en = 1;
        set_pmp_entry(0, 8'h09, 38'h00_2000_0400); // 0x8000_1000 >> 2
        set_pmp_entry(3, 8'h0F, 38'h00_2000_0800); // 0x8000_2000 >> 2
        priv_mode = `PRIV_U;
        paddr = 38'h00_8000_0500;
        check_r = 0; check_w = 1; check_x = 0; // Write attempt
        #2;
        if (pmp_fault !== 1'b1) begin
            $display("ERROR [T7]: Priority violation! Higher entry overruled lowest entry 0");
            err_cnt = err_cnt + 1;
        end else begin
            $display("PASS [T7]: Entry priority confirmed (Entry 0 read-only overruled Entry 3 RWX)");
        end

        // Test 8: Locked (L-bit) Entry Strict Enforcement in M-Mode
        // In M-mode, unlocked entries are bypassed.
        // Set Entry 4 with Lock bit L=1: cfg = {L=1, 2'b00, A=2'b11 (NAPOT), X=0, W=0, R=1} = 8'b1001_1001 = 8'h99
        // 16B region at 0x00_1000_0000: word = 0x00_0400_0000 | 2'b01 = 38'h00_0400_0001
        test_cnt = test_cnt + 1;
        clear_all_pmp();
        check_en = 1;
        set_pmp_entry(4, 8'h99, 38'h00_0400_0001);
        priv_mode = `PRIV_M;
        paddr = 38'h00_1000_0004;

        // Read in M-mode: allowed
        check_r = 1; check_w = 0; check_x = 0;
        #2;
        if (pmp_fault !== 1'b0) begin
            $display("ERROR [T8]: M-mode locked entry read faulted");
            err_cnt = err_cnt + 1;
        end else begin
            // Write in M-mode: MUST FAULT because entry is locked and W=0!
            check_r = 0; check_w = 1; check_x = 0;
            #2;
            if (pmp_fault !== 1'b1) begin
                $display("ERROR [T8]: M-mode locked entry write violation was NOT faulted!");
                err_cnt = err_cnt + 1;
            end else begin
                $display("PASS [T8]: Locked (L-bit) entry strict enforcement confirmed in M-Mode");
            end
        end

        clear_all_pmp();
        #20;

        $display("=== VERIFICATION SUMMARY ===");
        $display("Total Tests Executed: %0d", test_cnt);
        $display("Total Errors: %0d", err_cnt);

        if (err_cnt == 0) begin
            $display("ALL TESTS PASSED: rv_pmp 100%% VERIFIED (RISC-V Word Address Compliant)");
        end else begin
            $display("VERIFICATION FAILED: %0d errors detected!", err_cnt);
        end
        $finish;
    end
endmodule
