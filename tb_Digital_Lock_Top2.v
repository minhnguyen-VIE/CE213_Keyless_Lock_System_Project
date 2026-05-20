`timescale 1ns/1ps
`include "Common_Params.v"

// =============================================================================
// Testbench : tb_Digital_Lock_Top2
// DUT       : Digital_Lock_Top2 (Switch_Input + Main_FSM + LCD + Memory + Checker)
// M?c tiêu  : Self-checking PASS/FAIL, 19 test cases, 5 nhóm
// =============================================================================

module tb_Digital_Lock_Top2;

// =============================================================================
// PH?N 1: KHAI BÁO TÍN HI?U
// =============================================================================

    reg        clk;
    reg [3:0]  KEY;    // KEY[0]=rst_n, KEY[1]=digit/ENT, KEY[2]=BACK, KEY[3]=CLR
    reg [9:0]  SW;     // SW[3:0]=digit, SW[7]=change_btn, SW[8]=mode, SW[9]=HIDE

    wire [7:0] LCD_DATA;
    wire       LCD_EN, LCD_RS, LCD_RW, LCD_ON;
    wire       LEDG;
    wire [4:0] LEDR;
    wire [3:0] LEDG_SW;
    wire       LEDG_MODE, LEDG_HIDE;
    wire [2:0] state_dbg;

    // State encoding ? kh?p v?i Main_FSM
    localparam [2:0]
        S_RESET    = 3'd0,
        S_SET_NEW  = 3'd1,
        S_IDLE     = 3'd2,
        S_CHANGE   = 3'd3,
        S_CHECK    = 3'd4,
        S_UNLOCKED = 3'd5,
        S_ERROR    = 3'd6,
        S_LOCKOUT  = 3'd7;

    // B? ??m k?t qu?
    integer pass_cnt  = 0;
    integer fail_cnt  = 0;
    integer total_cnt = 0;
    integer i;

// =============================================================================
// PH?N 2: KH?I T?O DUT
// =============================================================================

    Digital_Lock_Top2 dut (
        .CLOCK_50  (clk),
        .KEY       (KEY),
        .SW        (SW),
        .LCD_DATA  (LCD_DATA),
        .LCD_EN    (LCD_EN),
        .LCD_RS    (LCD_RS),
        .LCD_RW    (LCD_RW),
        .LCD_ON    (LCD_ON),
        .LEDG      (LEDG),
        .LEDR      (LEDR),
        .LEDG_SW   (LEDG_SW),
        .LEDG_MODE (LEDG_MODE),
        .LEDG_HIDE (LEDG_HIDE),
        .state_dbg (state_dbg)
    );

    // Rút ng?n lockout xu?ng 200 cycles ?? mô ph?ng nhanh
    defparam dut.u_fsm.LOCKOUT_CYCLES = 32'd200;

    // Clock 50 MHz ? chu k? 20ns
    initial clk = 0;
    always #10 clk = ~clk;

// =============================================================================
// PH?N 3: TASK TH? VI?N
// =============================================================================

    // ------------------------------------------------------------------
    // Task c? b?n: nh?n/nh? 1 KEY (active-low)
    // ------------------------------------------------------------------
    task press_hw_key;
        input integer key_idx;
        begin
            @(negedge clk);             // ??ng b? c?nh xu?ng
            KEY[key_idx] = 1'b0;        // Nh?n
            repeat(3) @(posedge clk);   // Gi? 3 cycles (?? edge detector)
            KEY[key_idx] = 1'b1;        // Nh?
            repeat(5) @(posedge clk);   // ??i FSM x? lý
        end
    endtask

    // ------------------------------------------------------------------
    // Task: Nh?p 1 ch? s? (SW[8]=0, ??t SW[3:0], nh?n KEY[1])
    // ------------------------------------------------------------------
    task input_digit;
        input [3:0] digit;
        begin
            @(negedge clk);
            SW[8]   = 1'b0;             // Ch? ?? nh?p s?
            SW[3:0] = digit;
            repeat(2) @(posedge clk);   // SW ?n ??nh
            press_hw_key(1);            // KEY[1] = nh?p s?
        end
    endtask

    // ------------------------------------------------------------------
    // Task: G?i ENT (SW[8]=1, nh?n KEY[1])
    // ------------------------------------------------------------------
    task send_ent;
        begin
            @(negedge clk);
            SW[8] = 1'b1;               // Ch? ?? ENT
            repeat(2) @(posedge clk);
            press_hw_key(1);            // KEY[1] = ENT
            SW[8] = 1'b0;               // Tr? v? ch? ?? nh?p s?
            repeat(10) @(posedge clk);  // ??i FSM ch?y qua S_CHECK
        end
    endtask

    // ------------------------------------------------------------------
    // Task: Nh?p chu?i 6 ch? s? r?i ENT
    // ------------------------------------------------------------------
    task input_password;
        input [3:0] d0, d1, d2, d3, d4, d5;
        begin
            input_digit(d0);
            input_digit(d1);
            input_digit(d2);
            input_digit(d3);
            input_digit(d4);
            input_digit(d5);
            send_ent;
        end
    endtask

    // ------------------------------------------------------------------
    // Task: Nh?n BACK
    // ------------------------------------------------------------------
    task press_back;
        begin
            press_hw_key(2);
        end
    endtask

    // ------------------------------------------------------------------
    // Task: Nh?n CLR
    // ------------------------------------------------------------------
    task press_clr;
        begin
            press_hw_key(3);
        end
    endtask

    // ------------------------------------------------------------------
    // Task: G?t SW[7] ?? trigger change_pass (edge detector)
    // ------------------------------------------------------------------
    task press_change_btn;
        begin
            @(negedge clk);
            SW[7] = 1'b1;               // G?t lên ? posedge
            repeat(5) @(posedge clk);   // Gi? ?? ?? edge detector b?t
            // Không g?t xu?ng (toggle switch gi? nguyên)
        end
    endtask

    // ------------------------------------------------------------------
    // Task: G?t SW[9] toggle HIDE
    // ------------------------------------------------------------------
    task toggle_hide;
        begin
            @(negedge clk);
            SW[9] = ~SW[9];             // ??o
            repeat(5) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Task: Th?c hi?n reset
    // ------------------------------------------------------------------
    task do_reset;
        begin
            @(negedge clk);
            KEY[0] = 1'b0;
            repeat(5) @(posedge clk);
            KEY[0] = 1'b1;
            repeat(10) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Task: CHECK STATE
    // ------------------------------------------------------------------
    task check_state;
        input [2:0]   expected;
        input [255:0] name;
        begin
            total_cnt = total_cnt + 1;
            if (state_dbg === expected) begin
                $display("  [PASS] TC%02d: %s", total_cnt, name);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] TC%02d: %s", total_cnt, name);
                $display("         Expected state=%0d (%s), Got state=%0d",
                         expected, state_name(expected), state_dbg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Task: CHECK LED
    // ------------------------------------------------------------------
    task check_led;
        input        exp_ledg;
        input [4:0]  exp_ledr;
        input [255:0] name;
        begin
            total_cnt = total_cnt + 1;
            if (LEDG === exp_ledg && LEDR === exp_ledr) begin
                $display("  [PASS] TC%02d: %s", total_cnt, name);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] TC%02d: %s", total_cnt, name);
                $display("         Expected LEDG=%b LEDR=%05b, Got LEDG=%b LEDR=%05b",
                         exp_ledg, exp_ledr, LEDG, LEDR);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Task: CHECK STATE + LED cùng lúc
    // ------------------------------------------------------------------
    task check_all;
        input [2:0]   exp_state;
        input         exp_ledg;
        input [4:0]   exp_ledr;
        input [255:0] name;
        begin
            total_cnt = total_cnt + 1;
            if (state_dbg === exp_state && LEDG === exp_ledg && LEDR === exp_ledr) begin
                $display("  [PASS] TC%02d: %s", total_cnt, name);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] TC%02d: %s", total_cnt, name);
                if (state_dbg !== exp_state)
                    $display("         State: Expected=%0d Got=%0d", exp_state, state_dbg);
                if (LEDG !== exp_ledg)
                    $display("         LEDG:  Expected=%b Got=%b", exp_ledg, LEDG);
                if (LEDR !== exp_ledr)
                    $display("         LEDR:  Expected=%05b Got=%05b", exp_ledr, LEDR);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Hàm: tr? tên state ?? in ra cho d? ??c
    // ------------------------------------------------------------------
    function [63:0] state_name;
        input [2:0] s;
        begin
            case (s)
                S_RESET    : state_name = "RESET   ";
                S_SET_NEW  : state_name = "SET_NEW ";
                S_IDLE     : state_name = "IDLE    ";
                S_CHANGE   : state_name = "CHANGE  ";
                S_CHECK    : state_name = "CHECK   ";
                S_UNLOCKED : state_name = "UNLOCKED";
                S_ERROR    : state_name = "ERROR   ";
                S_LOCKOUT  : state_name = "LOCKOUT ";
                default    : state_name = "UNKNOWN ";
            endcase
        end
    endfunction

// =============================================================================
// PH?N 4: K?CH B?N KI?M TH?
// =============================================================================

    initial begin
        // Kh?i t?o
        KEY  = 4'b1111;     // T?t c? KEY nh? (active-low ? 1)
        SW   = 10'd0;

        $display("==========================================================");
        $display("  TESTBENCH: Digital_Lock_Top2 ? Self-Checking PASS/FAIL  ");
        $display("  LOCKOUT_CYCLES overridden = 200 cycles                  ");
        $display("==========================================================");

        // ==================================================================
        // NHÓM 1: KH?I ??NG & THI?T L?P M?T KH?U
        // ==================================================================
        $display("\n[GROUP 1] Khoi dong & Thiet lap mat khau lan dau");

        // TC01: Power-on reset
        do_reset;
        check_all(S_SET_NEW, 0, 5'd0, "TC01: Reset -> vao S_SET_NEW, LEDG=0, LEDR=0");

        // TC02: Thi?t l?p m?t kh?u 123456 ? ENT ? v? IDLE
        input_password(4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6);
        check_all(S_IDLE, 0, 5'd0, "TC02: Nhap 123456+ENT -> luu pass, ve S_IDLE");

        // TC03: ENT khi ch?a ?? 6 s? ? FSM không chuy?n
        input_digit(4'd1);
        input_digit(4'd2);
        input_digit(4'd3);
        send_ent;           // Ch? 3 s?, ENT b? b? qua
        check_state(S_IDLE, "TC03: ENT khi chi co 3 so -> o lai S_IDLE (ENT bi ignore)");

        // TC04: BACK xóa 1 s? ? digit_count gi?m, FSM ? l?i
        // (?ang trong IDLE, ?ã nh?p 3 s? t? TC03 ch?a confirm)
        press_back;
        check_state(S_IDLE, "TC04: BACK xoa 1 so -> FSM o lai S_IDLE");

        // TC05: CLR xóa h?t ? reset buffer
        press_clr;
        check_state(S_IDLE, "TC05: CLR xoa het -> FSM o lai S_IDLE");

        // ==================================================================
        // NHÓM 2: M? KHÓA ?ÚNG M?T KH?U
        // ==================================================================
        $display("\n[GROUP 2] Mo khoa dung mat khau");

        // TC06: M? khóa ?úng 123456
        input_password(4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6);
        check_all(S_UNLOCKED, 1, 5'd0, "TC06: Nhap DUng 123456 -> S_UNLOCKED, LEDG=1");

        // TC07: ?óng c?a b?ng ENT
        send_ent;
        check_all(S_IDLE, 0, 5'd0, "TC07: ENT khi UNLOCKED -> dong cua, ve S_IDLE");

        // TC08: Toggle HIDE trong lúc nh?p
        input_digit(4'd1);
        input_digit(4'd2);
        toggle_hide;        // G?t SW[9]
        check_state(S_IDLE, "TC08: Toggle HIDE khi dang nhap -> o lai S_IDLE");
        press_clr;          // D?n buffer tr??c test ti?p

        // ==================================================================
        // NHÓM 3: NH?P SAI & LOCKOUT
        // ==================================================================
        $display("\n[GROUP 3] Nhap sai & Lockout");

        // TC09: Sai l?n 1
        input_password(4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0);   // 000000 ? 123456
        repeat(5) @(posedge clk);   // ??i qua S_ERROR v? S_IDLE
        check_all(S_IDLE, 0, 5'b00001, "TC09: Sai lan 1 -> S_IDLE, LEDR[0]=1");

        // TC10: Sai l?n 2, 3, 4
        for (i = 2; i <= 4; i = i + 1) begin
            input_password(4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0);
            repeat(5) @(posedge clk);
        end
        check_all(S_IDLE, 0, 5'b01111, "TC10: Sai 4 lan -> S_IDLE, LEDR[3:0]=1111");

        // TC11: Sai l?n 5 ? LOCKOUT
        input_password(4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0);
        repeat(5) @(posedge clk);
        check_all(S_LOCKOUT, 0, 5'b11111, "TC11: Sai lan 5 -> S_LOCKOUT, LEDR=11111");

        // TC12: Phím b? b? qua trong LOCKOUT
        input_digit(4'd1);
        input_digit(4'd2);
        check_state(S_LOCKOUT, "TC12: Nhap phim trong LOCKOUT -> FSM van o S_LOCKOUT");

        // TC13: Thoát LOCKOUT sau 200 cycles (defparam)
        repeat(250) @(posedge clk);     // Ch? qua 200 cycles
        check_all(S_IDLE, 0, 5'd0, "TC13: Het LOCKOUT 200cy -> ve S_IDLE, LEDR=0");

        // ==================================================================
        // NHÓM 4: ??I M?T KH?U
        // ==================================================================
        $display("\n[GROUP 4] Doi mat khau");

        // TC14: ??i m?t kh?u thành công 123456 ? 654321
        SW[7] = 1'b0;       // ??m b?o SW[7] ?ang th?p tr??c khi g?t
        repeat(3) @(posedge clk);
        press_change_btn;   // G?t SW[7] lên ? trigger S_CHANGE
        check_state(S_CHANGE, "TC14: Gat SW[7] -> vao S_CHANGE xac nhan pass cu");

        input_password(4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6);   // Pass c? ?úng
        check_state(S_SET_NEW, "TC15: Dung pass cu -> vao S_SET_NEW nhap pass moi");

        input_password(4'd6, 4'd5, 4'd4, 4'd3, 4'd2, 4'd1);   // Pass m?i: 654321
        check_all(S_IDLE, 0, 5'd0, "TC16: Luu pass moi -> ve S_IDLE");

        // Xác nh?n m?t kh?u m?i ho?t ??ng
        input_password(4'd6, 4'd5, 4'd4, 4'd3, 4'd2, 4'd1);
        check_all(S_UNLOCKED, 1, 5'd0, "TC17: Mo khoa bang pass moi 654321 -> UNLOCKED");
        send_ent;           // ?óng c?a

        // TC18: ??i m?t kh?u v?i pass c? sai
        SW[7] = 1'b0;
        repeat(3) @(posedge clk);
        press_change_btn;
        input_password(4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6);   // Pass c? SAI (?ã ??i r?i)
        repeat(5) @(posedge clk);
        check_state(S_IDLE, "TC18: Pass cu sai khi doi -> S_ERROR->S_IDLE, khong vao S_SET_NEW");

        // ==================================================================
        // NHÓM 5: EDGE CASES
        // ==================================================================
        $display("\n[GROUP 5] Edge cases");

        // TC19: Reset gi?a ch?ng nh?p
        input_digit(4'd1);
        input_digit(4'd2);
        input_digit(4'd3);
        do_reset;
        check_all(S_SET_NEW, 0, 5'd0,
            "TC19: Reset giua chung -> S_SET_NEW, digit_count=0, LEDR=0");

        // ==================================================================
        // T?NG K?T
        // ==================================================================
        $display("\n==========================================================");
        $display("  TEST REPORT SUMMARY                                     ");
        $display("==========================================================");
        $display("  Total  : %0d", total_cnt);
        $display("  PASS   : %0d", pass_cnt);
        $display("  FAIL   : %0d", fail_cnt);
        $display("  Rate   : %0d%%", (pass_cnt * 100) / total_cnt);
        $display("----------------------------------------------------------");
        if (fail_cnt == 0)
            $display("  >> VERDICT: ALL PASS -- He thong hoat dong chinh xac <<");
        else
            $display("  >> VERDICT: %0d FAILURES -- Kiem tra lai module! <<", fail_cnt);
        $display("==========================================================\n");

        $stop;
    end

    // Timeout toàn c?c: d?ng n?u mô ph?ng ch?y quá 10ms
    initial begin
        #10_000_000;
        $display("[TIMEOUT] Mo phong chay qua 10ms, co the bi treo o S_LOCKOUT!");
        $stop;
    end

endmodule