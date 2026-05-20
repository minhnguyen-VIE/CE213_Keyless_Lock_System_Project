`include "Common_Params.v"

module Main_FSM (
    input  wire        clk,
    input  wire        rst_n,

    // Keypad_Scanner
    input  wire        key_valid,
    input  wire [3:0]  key_code,
    input  wire        is_function,

    // Code_Checker
    input  wire        match_flag,
    output reg         en_compare,
    output reg         clear_flag,
    output reg  [23:0] input_buffer,

    // Password_Memory
    input  wire        pwd_is_set,
    output reg         write_en,
    output reg  [23:0] new_password,

    // LCD_Driver
    output reg  [127:0] lcd_line1,
    output reg  [127:0] lcd_line2,
    output reg          lcd_update,

    // Ph?n c?ng DE2
    input  wire        change_pass_btn,
    output reg         unlock_led,
    output reg  [4:0]  error_leds,

    // Debug SignalTap
    output wire [2:0]  state_out
);

    localparam [2:0]
        S_RESET    = 3'd0,
        S_SET_NEW  = 3'd1,
        S_IDLE     = 3'd2,
        S_CHANGE   = 3'd3,
        S_CHECK    = 3'd4,
        S_UNLOCKED = 3'd5,
        S_ERROR    = 3'd6,
        S_LOCKOUT  = 3'd7;

    reg [2:0] state;
    assign state_out = state;

    reg [2:0]  digit_count;
    reg [2:0]  error_count;
    reg        change_pass;
    reg [31:0] lockout_timer;
    reg        hide_mode;
    reg        btn_prev;
    reg        check_wait;

    wire btn_posedge = change_pass_btn && !btn_prev;

    parameter [31:0] LOCKOUT_CYCLES = 32'd3_000_000_000;
    localparam [2:0] MAX_ERRORS     = 3'd5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_prev <= 1'b0;
        else        btn_prev <= change_pass_btn;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_RESET;
            digit_count   <= 3'd0;
            error_count   <= 3'd0;
            change_pass   <= 1'b0;
            lockout_timer <= 32'd0;
            hide_mode     <= 1'b1;
            input_buffer  <= 24'd0;
            new_password  <= 24'd0;
            en_compare    <= 1'b0;
            clear_flag    <= 1'b0;
            write_en      <= 1'b0;
            unlock_led    <= 1'b0;
            error_leds    <= 5'd0;
            lcd_line1     <= `MSG_IDLE;
            lcd_line2     <= {16{8'h20}};
            lcd_update    <= 1'b0;
            check_wait    <= 1'b0;
        end else begin
            en_compare <= 1'b0;
            clear_flag <= 1'b0;
            write_en   <= 1'b0;
            lcd_update <= 1'b0;

            case (state)
                S_RESET: begin
                    error_count   <= 3'd0;
                    digit_count   <= 3'd0;
                    change_pass   <= 1'b0;
                    input_buffer  <= 24'd0;
                    unlock_led    <= 1'b0;
                    error_leds    <= 5'd0;
                    hide_mode     <= 1'b1;
                    check_wait    <= 1'b0;

                    if (!pwd_is_set) begin
                        change_pass <= 1'b1;
                        lcd_line1   <= `MSG_SET_INIT;
                    end else begin
                        lcd_line1   <= `MSG_IDLE;
                    end
                    lcd_line2  <= {16{8'h20}};
                    lcd_update <= 1'b1;
                    state      <= S_SET_NEW;
                end

                S_SET_NEW: begin
                    unlock_led <= 1'b0;
                    if (key_valid) begin
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= update_line2(digit_count, key_code, hide_mode, input_buffer);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= clear_last(digit_count - 1'b1);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= {16{8'h20}};
                                lcd_update   <= 1'b1;
                            end
                            `KEY_ENT: begin
                                if (digit_count == 3'd6) begin
                                    new_password <= input_buffer;
                                    write_en     <= 1'b1;
                                    change_pass  <= 1'b0;
                                    digit_count  <= 3'd0;
                                    input_buffer <= 24'd0;
                                    lcd_line1    <= `MSG_IDLE;
                                    lcd_line2    <= {16{8'h20}};
                                    lcd_update   <= 1'b1;
                                    state        <= S_IDLE;
                                end
                            end
                            default: ;
                        endcase
                    end
                end

                S_IDLE: begin
                    if (btn_posedge) begin
                        change_pass  <= 1'b1;
                        digit_count  <= 3'd0;
                        input_buffer <= 24'd0;
                        lcd_line1    <= `MSG_CHG_OLD;
                        lcd_line2    <= {16{8'h20}};
                        lcd_update   <= 1'b1;
                        state        <= S_CHANGE;
                    end else if (key_valid) begin
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= update_line2(digit_count, key_code, hide_mode, input_buffer);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= clear_last(digit_count - 1'b1);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= {16{8'h20}};
                                lcd_update   <= 1'b1;
                            end
                            `KEY_HIDE: begin
                                hide_mode  <= ~hide_mode;
                                lcd_update <= 1'b1;
                                lcd_line2  <= rebuild_line2(digit_count, input_buffer, ~hide_mode);
                            end
                            `KEY_ENT: begin
                                if (digit_count == 3'd6) begin
                                    en_compare <= 1'b1;
                                    state      <= S_CHECK;
                                end
                            end
                            default: ;
                        endcase
                    end
                end

                S_CHANGE: begin
                    if (key_valid) begin
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= update_line2(digit_count, key_code, hide_mode, input_buffer);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= clear_last(digit_count - 1'b1);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= {16{8'h20}};
                                lcd_update   <= 1'b1;
                            end
                            `KEY_ENT: begin
                                if (digit_count == 3'd6) begin
                                    en_compare <= 1'b1;
                                    state      <= S_CHECK;
                                end
                            end
                            default: ;
                        endcase
                    end
                end

                S_CHECK: begin
                    if (!check_wait) begin
                        check_wait <= 1'b1;
                    end else begin
                        check_wait   <= 1'b0;
                        clear_flag   <= 1'b1;
                        digit_count  <= 3'd0;
                        input_buffer <= 24'd0;

                        if (match_flag) begin
                            if (change_pass) begin
                                lcd_line1  <= `MSG_SET_NEW;
                                lcd_line2  <= {16{8'h20}};
                                lcd_update <= 1'b1;
                                state      <= S_SET_NEW;
                            end else begin
                                unlock_led <= 1'b1;
                                lcd_line1  <= `MSG_CORRECT;
                                lcd_line2  <= `MSG_UNLOCKED;
                                lcd_update <= 1'b1;
                                state      <= S_UNLOCKED;
                            end
                        end else begin
                            state <= S_ERROR;
                        end
                    end
                end

                S_UNLOCKED: begin
                    unlock_led  <= 1'b1;
                    error_count <= 3'd0;
                    error_leds  <= 5'd0;

                    if (key_valid && key_code == `KEY_ENT) begin
                        unlock_led   <= 1'b0;
                        digit_count  <= 3'd0;
                        input_buffer <= 24'd0;
                        lcd_line1    <= `MSG_IDLE;
                        lcd_line2    <= {16{8'h20}};
                        lcd_update   <= 1'b1;
                        state        <= S_IDLE;
                    end
                end

                S_ERROR: begin
                    input_buffer <= 24'd0;
                    digit_count  <= 3'd0;

                    if (error_count < MAX_ERRORS - 1) begin
                        error_count <= error_count + 1'b1;
                        error_leds  <= {error_leds[3:0], 1'b1};
                        lcd_line1   <= `MSG_WRONG;
                        lcd_line2   <= {16{8'h20}};
                        lcd_update  <= 1'b1;
                        state       <= S_IDLE;
                    end else begin
                        error_count   <= 3'd0;
                        error_leds    <= 5'b11111;
                        lockout_timer <= 32'd0;
                        lcd_line1     <= `MSG_LOCKED;
                        lcd_line2     <= {16{8'h20}};
                        lcd_update    <= 1'b1;
                        state         <= S_LOCKOUT;
                    end
                end

                S_LOCKOUT: begin
                    unlock_led    <= 1'b0;
                    lockout_timer <= lockout_timer + 1'b1;

                    if (lockout_timer >= LOCKOUT_CYCLES - 1) begin
                        lockout_timer <= 32'd0;
                        error_count   <= 3'd0;
                        error_leds    <= 5'd0;
                        digit_count   <= 3'd0;
                        input_buffer  <= 24'd0;
                        change_pass   <= 1'b0;
                        lcd_line1     <= `MSG_IDLE;
                        lcd_line2     <= {16{8'h20}};
                        lcd_update    <= 1'b1;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

    // Hàm t?o mã kí t? dòng 2
    function automatic [7:0] char_at;
        input [2:0] pos;
        input [2:0] filled;
        input [3:0] new_key;
        input       hide;
        input [23:0] in_buf;
        begin
            if (pos < filled - 1) begin
                char_at = hide ? 8'h2A : (8'h30 + in_buf[23 - pos*4 -: 4]);
            end else if (pos == filled - 1) begin
                char_at = hide ? 8'h2A : (8'h30 + new_key);
            end else begin
                char_at = 8'h5F;
            end
        end
    endfunction

    function automatic [127:0] update_line2;
        input [2:0]  digit_before;
        input [3:0]  new_key;
        input        hide;
        input [23:0] in_buf;
        reg [2:0] filled;
        begin
            filled = digit_before + 1'b1;
            update_line2 = {
                char_at(3'd0, filled, new_key, hide, in_buf), 8'h20,
                char_at(3'd1, filled, new_key, hide, in_buf), 8'h20,
                char_at(3'd2, filled, new_key, hide, in_buf), 8'h20,
                char_at(3'd3, filled, new_key, hide, in_buf), 8'h20,
                char_at(3'd4, filled, new_key, hide, in_buf), 8'h20,
                char_at(3'd5, filled, new_key, hide, in_buf), 8'h20,
                32'h20202020
            };
        end
    endfunction

    function automatic [127:0] clear_last;
        input [2:0] new_count;
        begin
            clear_last = {
                (new_count > 3'd0 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd1 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd2 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd3 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd4 ? 8'h2A : 8'h5F), 8'h20,
                8'h5F, 8'h20,
                32'h20202020
            };
        end
    endfunction

    function automatic [127:0] rebuild_line2;
        input [2:0]  count;
        input [23:0] in_buf;
        input        hide;
        begin
            rebuild_line2 = {
                (count > 3'd0 ? (hide ? 8'h2A : 8'h30 + in_buf[23:20]) : 8'h5F), 8'h20,
                (count > 3'd1 ? (hide ? 8'h2A : 8'h30 + in_buf[19:16]) : 8'h5F), 8'h20,
                (count > 3'd2 ? (hide ? 8'h2A : 8'h30 + in_buf[15:12]) : 8'h5F), 8'h20,
                (count > 3'd3 ? (hide ? 8'h2A : 8'h30 + in_buf[11:8])  : 8'h5F), 8'h20,
                (count > 3'd4 ? (hide ? 8'h2A : 8'h30 + in_buf[7:4])   : 8'h5F), 8'h20,
                (count > 3'd5 ? (hide ? 8'h2A : 8'h30 + in_buf[3:0])   : 8'h5F), 8'h20,
                32'h20202020
            };
        end
    endfunction

endmodule