`include "Common_Params.v"

// =============================================================================
// Module  : Main_FSM
// Chức năng: Máy trạng thái trung tâm cho hệ thống khóa số điện tử
// Platform : Altera DE2, Cyclone II, 50 MHz
// Reset   : Bất đồng bộ, tích cực mức thấp (rst_n)
//
// Kiến trúc: Moore FSM — 3 always block
//   [1] Thanh ghi trạng thái         (sequential)
//   [2] Logic chuyển trạng thái      (combinational)
//   [3] Hành động + ngõ ra           (sequential, SINGLE DRIVER cho mọi reg)
//
// Chú ý DE2:
//   - change_pass_btn nối KEY1 (active-low trên DE2) → đảo lại nếu cần
//   - unlock_led  → LEDG0
//   - error_leds  → LEDR4:0
//   - lockout_timer 32-bit: 50e6 × 60 = 3_000_000_000 < 2^32 ✓
//   - en_compare, write_en: PULSE 1 cycle, Code_Checker latch ngay cycle tiếp
// =============================================================================

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
    input  wire        change_pass_btn,  // KEY1 (active-low, đảo ngoài top-level)
    output reg         unlock_led,       // LEDG0
    output reg  [4:0]  error_leds,       // LEDR4:0

    // Debug SignalTap
    output wire [2:0]  state_out
);

// =============================================================================
// KHAI BÁO TRẠNG THÁI
// =============================================================================

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

// =============================================================================
// THANH GHI NỘI
// =============================================================================

    reg [2:0]  digit_count;
    reg [2:0]  error_count;
    reg        change_pass;
    reg [31:0] lockout_timer;
    reg        hide_mode;
    reg        btn_prev;

    // Cạnh lên của nút đổi mật khẩu
    wire btn_posedge = change_pass_btn && !btn_prev;

    localparam [31:0] LOCKOUT_CYCLES = 32'd3_000_000_000;
    localparam [2:0]  MAX_ERRORS     = 3'd5;

// =============================================================================
// BLOCK 1: EDGE DETECTOR nút nhấn
// =============================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_prev <= 1'b0;
        else        btn_prev <= change_pass_btn;
    end

// =============================================================================
// BLOCK 2: THANH GHI TRẠNG THÁI
// =============================================================================
// Tất cả logic chuyển trạng thái được inline trực tiếp trong block sequential
// để tránh vấn đề "glitch" khi dùng 2-process FSM (next_state combinational
// không ổn định trước posedge). Với Quartus II Cyclone II, kiểu này an toàn hơn.

// =============================================================================
// BLOCK 3: LOGIC CHÍNH — 1 always block duy nhất điều khiển MỌI thanh ghi
// Quy tắc: mỗi thanh ghi chỉ được gán trong BLOCK NÀY để tránh multiple driver
// =============================================================================

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
        end else begin

            // ── Mặc định: xóa các pulse 1 cycle ──────────────────────────
            en_compare <= 1'b0;
            clear_flag <= 1'b0;
            write_en   <= 1'b0;
            lcd_update <= 1'b0;

            case (state)

                // ==========================================================
                // S0: RESET — Khởi tạo, chuyển ngay sang S1
                // ==========================================================
                S_RESET: begin
                    error_count   <= 3'd0;
                    digit_count   <= 3'd0;
                    change_pass   <= 1'b0;
                    input_buffer  <= 24'd0;
                    unlock_led    <= 1'b0;
                    error_leds    <= 5'd0;
                    hide_mode     <= 1'b1;

                    if (!pwd_is_set) begin
                        // Lần đầu khởi động: chưa có mật khẩu
                        change_pass <= 1'b1;
                        lcd_line1   <= `MSG_SET_INIT;
                    end else begin
                        lcd_line1   <= `MSG_IDLE;
                    end
                    lcd_line2  <= {16{8'h20}};
                    lcd_update <= 1'b1;
                    state      <= S_SET_NEW;    // Chuyển ngay, không chờ
                end

                // ==========================================================
                // S1: SET_NEW — Nhập mật khẩu mới (6 chữ số)
                // ==========================================================
                S_SET_NEW: begin
                    unlock_led <= 1'b0;

                    if (key_valid) begin
                        case (key_code)
                            // Nhập chữ số
                            `KEY_0, `KEY_1, `KEY_2, `KEY_3, `KEY_4,
                            `KEY_5, `KEY_6, `KEY_7, `KEY_8, `KEY_9: begin
                                if (digit_count < 3'd6) begin
                                    // Shift-in từ trái sang phải (MSB = số nhập đầu tiên)
                                    input_buffer <= {input_buffer[19:0], key_code};
                                    digit_count  <= digit_count + 1'b1;
                                    // Cập nhật dòng 2: hiển thị * hoặc số
                                    lcd_line2    <= update_line2(digit_count, key_code, hide_mode, input_buffer);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            // Xóa 1 số
                            `KEY_BACK: begin
                                if (digit_count > 3'd0) begin
                                    input_buffer <= {4'h0, input_buffer[23:4]};
                                    digit_count  <= digit_count - 1'b1;
                                    lcd_line2    <= clear_last(digit_count - 1'b1);
                                    lcd_update   <= 1'b1;
                                end
                            end
                            // Xóa hết
                            `KEY_CLR: begin
                                input_buffer <= 24'd0;
                                digit_count  <= 3'd0;
                                lcd_line2    <= {16{8'h20}};
                                lcd_update   <= 1'b1;
                            end
                            // Xác nhận: chỉ chấp nhận khi đủ 6 số
                            `KEY_ENT: begin
                                if (digit_count == 3'd6) begin
                                    new_password <= input_buffer;
                                    write_en     <= 1'b1;   // Pulse: ghi vào Memory
                                    change_pass  <= 1'b0;
                                    digit_count  <= 3'd0;
                                    input_buffer <= 24'd0;
                                    lcd_line1    <= `MSG_IDLE;
                                    lcd_line2    <= {16{8'h20}};
                                    lcd_update   <= 1'b1;
                                    state        <= S_IDLE;
                                end
                                // Nếu chưa đủ 6 số: bỏ qua
                            end
                            default: ; // KEY_HIDE không dùng ở mode SET
                        endcase
                    end
                end

                // ==========================================================
                // S2: IDLE — Chờ nhập mật khẩu hoặc nút đổi pass
                // ==========================================================
                S_IDLE: begin
                    error_leds <= error_count;

                    // Ưu tiên 1: Nút đổi mật khẩu
                    if (btn_posedge) begin
                        change_pass  <= 1'b1;
                        digit_count  <= 3'd0;
                        input_buffer <= 24'd0;
                        lcd_line1    <= `MSG_CHG_OLD;
                        lcd_line2    <= {16{8'h20}};
                        lcd_update   <= 1'b1;
                        state        <= S_CHANGE;

                    // Ưu tiên 2: Nhập phím
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
                                // Vẽ lại dòng 2 với mode mới
                                lcd_line2  <= rebuild_line2(digit_count, input_buffer, ~hide_mode);
                            end
                            `KEY_ENT: begin
                                if (digit_count == 3'd6) begin
                                    en_compare <= 1'b1;     // Pulse: kích hoạt so sánh
                                    state      <= S_CHECK;
                                end
                            end
                            default: ;
                        endcase
                    end
                end

                // ==========================================================
                // S3: CHANGE_MODE — Nhập mật khẩu cũ để xác nhận
                // ==========================================================
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

                // ==========================================================
                // S4: CHECK_PASS — Đọc kết quả từ Code_Checker
                //
                // Timing: en_compare pulse ở cuối S_IDLE/S_CHANGE
                //         → Code_Checker tính và set match_flag ở cycle kế
                //         → FSM vào S_CHECK ở cycle kế → đọc match_flag ngay
                //
                // Lưu ý: KHÔNG pulse en_compare ở đây nữa (đã pulse khi chuyển)
                // ==========================================================
                S_CHECK: begin
                    clear_flag   <= 1'b1;       // Pulse: reset match_flag sau khi đọc
                    digit_count  <= 3'd0;
                    input_buffer <= 24'd0;

                    if (match_flag) begin
                        if (change_pass) begin
                            // Đúng mật khẩu cũ → cho nhập mật khẩu mới
                            lcd_line1  <= `MSG_SET_NEW;
                            lcd_line2  <= {16{8'h20}};
                            lcd_update <= 1'b1;
                            state      <= S_SET_NEW;
                        end else begin
                            // Đúng mật khẩu → mở khóa
                            unlock_led <= 1'b1;
                            lcd_line1  <= `MSG_CORRECT;
                            lcd_line2  <= `MSG_UNLOCKED;
                            lcd_update <= 1'b1;
                            state      <= S_UNLOCKED;
                        end
                    end else begin
                        // Sai mật khẩu
                        state <= S_ERROR;
                    end
                end

                // ==========================================================
                // S5: UNLOCKED — Mở khóa, chờ đóng cửa
                // ==========================================================
                S_UNLOCKED: begin
                    unlock_led  <= 1'b1;
                    error_count <= 3'd0;
                    error_leds  <= 5'd0;

                    // Nhấn ENT để đóng cửa
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

                // ==========================================================
                // S6: ERROR_HANDLER — Nhập sai, tăng bộ đếm
                // ==========================================================
                S_ERROR: begin
                    input_buffer <= 24'd0;
                    digit_count  <= 3'd0;

                    if (error_count < MAX_ERRORS - 1) begin
                        // Còn lượt nhập
                        error_count <= error_count + 1'b1;
                        error_leds  <= error_count + 1'b1;
                        lcd_line1   <= `MSG_WRONG;
                        lcd_line2   <= {16{8'h20}};
                        lcd_update  <= 1'b1;
                        state       <= S_IDLE;
                    end else begin
                        // Hết lượt → khóa
                        error_count   <= 3'd0;
                        error_leds    <= 5'b11111;
                        lockout_timer <= 32'd0;
                        lcd_line1     <= `MSG_LOCKED;
                        lcd_line2     <= {16{8'h20}};
                        lcd_update    <= 1'b1;
                        state         <= S_LOCKOUT;
                    end
                end

                // ==========================================================
                // S7: LOCKOUT — Đóng băng 60 giây, bỏ qua mọi phím nhấn
                // ==========================================================
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

// =============================================================================
// PHẦN 4: HÀM LCD — Tính dòng 2 hiển thị ký tự nhập
//
// Dòng 2 layout (12 ký tự dùng, 4 space cuối):
//   [c0][sp][c1][sp][c2][sp][c3][sp][c4][sp][c5][sp][sp][sp][sp][sp]
//   Mỗi ký tự có thể là: '*' (hide=1), '0'..'9' (hide=0), '_' (chưa nhập)
//
// Dùng function để tránh lặp code. Function này SYNTHESIZABLE vì:
//   - Không dùng vòng lặp với biến dynamic
//   - Chỉ dùng phép gán bit tĩnh
// =============================================================================

    // Trả về ký tự ASCII của vị trí pos (0..5):
    //   - Nếu pos < count_after: đã nhập → '*' hoặc chữ số
    //   - Nếu pos == count_after: vừa nhập (key_code mới)
    //   - Nếu pos > count_after: chưa nhập → '_'
    // Trả về ký tự ASCII của vị trí pos (0..5):
    //   - Nếu pos < count_after: đã nhập → '*' hoặc chữ số
    //   - Nếu pos == count_after: vừa nhập (key_code mới)
    //   - Nếu pos > count_after: chưa nhập → '_'
    function automatic [7:0] char_at;
        input [2:0] pos;            // Vị trí 0..5
        input [2:0] filled;         // Số ô đã điền (SAU khi thêm ký tự mới)
        input [3:0] new_key;        // Ký tự mới nhất
        input       hide;
        input [23:0] in_buf;        // Đã đổi từ buf -> in_buf
        begin
            if (pos < filled - 1) begin
                // Ô đã nhập từ trước (trong buffer)
                char_at = hide ? 8'h2A :    // '*'
                          (8'h30 + in_buf[23 - pos*4 -: 4]);  // '0'...'9'
            end else if (pos == filled - 1) begin
                // Ô vừa nhập (new_key)
                char_at = hide ? 8'h2A : (8'h30 + new_key);
            end else begin
                // Ô chưa nhập
                char_at = 8'h5F;    // '_'
            end
        end
    endfunction

    function automatic [127:0] update_line2;
        input [2:0]  digit_before;  // digit_count TRƯỚC khi nhập
        input [3:0]  new_key;
        input        hide;
        input [23:0] in_buf;        // Đã đổi từ buf -> in_buf
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
                32'h20202020    // 4 spaces padding
            };
        end
    endfunction

    // Xóa 1 ký tự (BACK): điền '_' vào vị trí vừa xóa
    function automatic [127:0] clear_last;
        input [2:0] new_count;      // digit_count SAU khi xóa
        begin
            clear_last = {
                (new_count > 3'd0 ? 8'h2A : 8'h5F), 8'h20,   // pos 0 (luôn hide vì không biết mode)
                (new_count > 3'd1 ? 8'h2A : 8'h5F), 8'h20,   // pos 1
                (new_count > 3'd2 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd3 ? 8'h2A : 8'h5F), 8'h20,
                (new_count > 3'd4 ? 8'h2A : 8'h5F), 8'h20,
                8'h5F, 8'h20,
                32'h20202020
            };
        end
    endfunction

    // Rebuild toàn bộ dòng 2 (dùng khi toggle KEY_HIDE)
    function automatic [127:0] rebuild_line2;
        input [2:0]  count;
        input [23:0] in_buf;        // Đã đổi từ buf -> in_buf
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