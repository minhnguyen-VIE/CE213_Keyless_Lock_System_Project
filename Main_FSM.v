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

    // Phần cứng DE2
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
    
    // Tín hiệu chống dội và bắt cạnh phím
    reg [21:0] debounce_timer; 
    reg        key_valid_prev; // Lưu trạng thái trước đó của phím

    parameter [31:0] LOCKOUT_CYCLES = 32'd3_000_000_000;
    localparam [2:0] MAX_ERRORS     = 3'd5;
    localparam [21:0] DEBOUNCE_TIME = 22'd500_000; // Giảm xuống 10ms để bấm mượt và nhanh hơn

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_prev       <= 1'b0;
            key_valid_prev <= 1'b0;
        end else begin
            btn_prev       <= change_pass_btn;
            key_valid_prev <= key_valid;
        end
    end

    // Tín hiệu kích hoạt CHỈ 1 XUNG DUY NHẤT khi nhấn xuống (Bất chấp giữ nút bao lâu)
    wire key_edge = key_valid & ~key_valid_prev;

    // =========================================================================
    // HÀM TẠO DÒNG 2 THÔNG MINH
    // =========================================================================
    function automatic [7:0] get_char;
        input [2:0] pos;      
        input [2:0] count;    
        input [23:0] din;
        input hide;
        reg [2:0] shift_idx;
        begin
            if (pos < count) begin
                shift_idx = count - 1'b1 - pos;
                if (hide) begin
                    get_char = 8'h2A; // In dấu *
                end else begin
                    case (shift_idx)
                        3'd0: get_char = 8'h30 + din[3:0];
                        3'd1: get_char = 8'h30 + din[7:4];
                        3'd2: get_char = 8'h30 + din[11:8];
                        3'd3: get_char = 8'h30 + din[15:12];
                        3'd4: get_char = 8'h30 + din[19:16];
                        3'd5: get_char = 8'h30 + din[23:20];
                        default: get_char = 8'h30;
                    endcase
                end
            end else begin
                get_char = 8'h5F; // In dấu _
            end
        end
    endfunction

    function automatic [127:0] build_line2;
        input [2:0]  count;
        input [23:0] din;
        input        hide;
        begin
            build_line2 = {
                get_char(3'd0, count, din, hide), 8'h20,
                get_char(3'd1, count, din, hide), 8'h20,
                get_char(3'd2, count, din, hide), 8'h20,
                get_char(3'd3, count, din, hide), 8'h20,
                get_char(3'd4, count, din, hide), 8'h20,
                get_char(3'd5, count, din, hide), 8'h20,
                32'h20202020
            };
        end
    endfunction
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_RESET;
            digit_count    <= 3'd0;
            error_count    <= 3'd0;
            change_pass    <= 1'b0;
            lockout_timer  <= 32'd0;
            hide_mode      <= 1'b0;
            input_buffer   <= 24'd0;
            new_password   <= 24'd0;
            en_compare     <= 1'b0;
            clear_flag     <= 1'b0;
            write_en       <= 1'b0;
            unlock_led     <= 1'b0;
            error_leds     <= 5'd0;
            lcd_line1      <= `MSG_IDLE;
            lcd_line2      <= {16{8'h20}};
            lcd_update     <= 1'b0;
            check_wait     <= 1'b0;
            debounce_timer <= 22'd0;
        end else begin
            en_compare <= 1'b0;
            clear_flag <= 1'b0;
            write_en   <= 1'b0;
            lcd_update <= 1'b0;

            // Xử lý bộ đếm lùi thời gian chống dội
            if (debounce_timer > 0) begin
                debounce_timer <= debounce_timer - 1'b1;
            end

            case (state)
                S_RESET: begin
                    error_count    <= 3'd0;
                    digit_count    <= 3'd0;
                    change_pass    <= 1'b0;
                    input_buffer   <= 24'd0;
                    unlock_led     <= 1'b0;
                    error_leds     <= 5'd0;
                    hide_mode      <= 1'b0; 
                    check_wait     <= 1'b0;
                    lockout_timer  <= 32'd0; 
                    lcd_line2      <= {16{8'h20}};
                    lcd_update     <= 1'b1;

                    if (!pwd_is_set) begin
                        change_pass <= 1'b1;
                        lcd_line1   <= `MSG_SET_INIT;
                        state       <= S_SET_NEW;
                    end else begin
                        lcd_line1   <= `MSG_IDLE;
                        state       <= S_IDLE;
                    end
                end

                S_SET_NEW: begin
                    unlock_led <= 1'b0;
                    if (key_edge && debounce_timer == 0) begin
                        debounce_timer <= DEBOUNCE_TIME; // Khóa phím 10ms
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= build_line2(digit_count + 1'b1, {input_buffer[19:0], key_code}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= build_line2(digit_count - 1'b1, {4'h0, input_buffer[23:4]}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= build_line2(3'd0, 24'd0, hide_mode);
                                lcd_update   <= 1'b1;
                            end
                            `KEY_HIDE: begin
                                hide_mode  <= ~hide_mode;
                                lcd_line2  <= build_line2(digit_count, input_buffer, ~hide_mode);
                                lcd_update <= 1'b1;
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
                    if ((change_pass_btn & ~btn_prev) && debounce_timer == 0) begin 
                        debounce_timer <= DEBOUNCE_TIME;
                        change_pass  <= 1'b1;
                        digit_count  <= 3'd0;
                        input_buffer <= 24'd0;
                        lcd_line1    <= `MSG_CHG_OLD;
                        lcd_line2    <= build_line2(3'd0, 24'd0, hide_mode);
                        lcd_update   <= 1'b1;
                        state        <= S_CHANGE;
                    end else if (key_edge && debounce_timer == 0) begin
                        debounce_timer <= DEBOUNCE_TIME; // Khóa phím 10ms
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= build_line2(digit_count + 1'b1, {input_buffer[19:0], key_code}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= build_line2(digit_count - 1'b1, {4'h0, input_buffer[23:4]}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= build_line2(3'd0, 24'd0, hide_mode);
                                lcd_update   <= 1'b1;
                            end
                            `KEY_HIDE: begin
                                hide_mode  <= ~hide_mode;
                                lcd_line2  <= build_line2(digit_count, input_buffer, ~hide_mode);
                                lcd_update <= 1'b1;
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
                    if (key_edge && debounce_timer == 0) begin
                        debounce_timer <= DEBOUNCE_TIME; // Khóa phím 10ms
                        case (key_code)
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    lcd_line2    <= build_line2(digit_count + 1'b1, {input_buffer[19:0], key_code}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= build_line2(digit_count - 1'b1, {4'h0, input_buffer[23:4]}, hide_mode);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= build_line2(3'd0, 24'd0, hide_mode);
                                lcd_update   <= 1'b1;
                            end
                            `KEY_HIDE: begin
                                hide_mode  <= ~hide_mode;
                                lcd_line2  <= build_line2(digit_count, input_buffer, ~hide_mode);
                                lcd_update <= 1'b1;
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
                                lcd_line2  <= build_line2(3'd0, 24'd0, hide_mode);
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

                    if (key_edge && key_code == `KEY_ENT && debounce_timer == 0) begin
                        debounce_timer <= DEBOUNCE_TIME;
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
                    end else state <= S_LOCKOUT;
					
                end

                default: state <= S_RESET;
            endcase
        end
    end
endmodule