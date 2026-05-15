`include "Common_Params.v"

// =============================================================================
// Module  : Digital_Lock_Top
// Chức năng: Top-level module khóa số điện tử — kết nối tất cả sub-module
// Platform : Altera DE2, Cyclone II EP2C35F672C6, 50 MHz
// Reset   : KEY0 (active-low)
//
// Pin mapping DE2:
//   CLOCK_50       → clk
//   KEY[0]         → rst_n         (active-low, giữ để reset)
//   KEY[1]         → change_pass_btn (active-low, đảo nội bộ)
//   GPIO_0[3:0]    → cols[3:0]     (ngõ vào từ bàn phím, pull-up trên DE2)
//   GPIO_0[7:4]    → rows[3:0]     (ngõ ra quét bàn phím)
//   LCD_DATA[7:0]  → lcd_data
//   LCD_EN         → lcd_en
//   LCD_RS         → lcd_rs
//   LCD_RW         → lcd_rw        (= GND, write-only)
//   LCD_ON         → lcd_on        (= VCC, luôn bật)
//   LEDG[0]        → unlock_led    (xanh lá: mở khóa)
//   LEDR[4:0]      → error_leds    (đỏ: số lần sai)
// =============================================================================

module Digital_Lock_Top (
    // --- Clock & Reset ---
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,             // KEY[0]=rst_n, KEY[1]=change_pass_btn

    // --- Bàn phím ma trận 4×4 ---
    input  wire [3:0]  cols,            // Cột (từ bàn phím, qua GPIO)
    output wire [3:0]  rows,            // Hàng (ra bàn phím, qua GPIO)

    // --- LCD HD44780 ---
    output wire [7:0]  LCD_DATA,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_ON,

    // --- LED ngõ ra ---
    output wire        LEDG,            // LEDG[0]: mở khóa
    output wire [4:0]  LEDR,            // LEDR[4:0]: đếm lỗi

    // --- Debug (tùy chọn, kết nối SignalTap) ---
    output wire [2:0]  state_dbg
);

// =============================================================================
// TÍN HIỆU NỘI BỘ
// =============================================================================

    // Clock & Reset
    wire clk    = CLOCK_50;
    wire rst_n  = KEY[0];               // KEY0 active-low → rst_n active-low ✓

    // Nút đổi mật khẩu: KEY1 active-low → đảo thành active-high cho Main_FSM
    wire change_pass_btn = ~KEY[1];

    // ── Keypad_Scanner → Main_FSM ──
    wire        key_valid;
    wire [3:0]  key_code;
    wire        is_function;

    // ── Main_FSM → Code_Checker ──
    wire        en_compare;
    wire        clear_flag;
    wire [23:0] input_buffer;

    // ── Main_FSM → Password_Memory ──
    wire        write_en;
    wire [23:0] new_password;

    // ── Password_Memory → Main_FSM & Code_Checker ──
    wire [23:0] stored_password;
    wire        pwd_is_set;

    // ── Code_Checker → Main_FSM ──
    wire        match_flag;

    // ── Main_FSM → LCD_Driver ──
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire         lcd_update;

    // ── Main_FSM → LED ──
    wire        unlock_led;
    wire [4:0]  error_leds;

// =============================================================================
// INSTANTIATION — 5 SUB-MODULE
// =============================================================================

    // ------------------------------------------------------------------
    // 1. Keypad_Scanner
    //    Quét ma trận 4×4, debounce 20ms, giải mã key_code
    // ------------------------------------------------------------------
    Keypad_Scanner u_keypad (
        .clk         (clk),
        .rst_n       (rst_n),
        .cols        (cols),
        .rows        (rows),
        .key_code    (key_code),
        .key_valid   (key_valid),
        .is_function (is_function)
    );

    // ------------------------------------------------------------------
    // 2. Password_Memory
    //    Lưu mật khẩu 24-bit trong register (tồn tại trong FF, mất khi power-off)
    //    write_en: pulse 1 cycle để ghi new_password
    //    pwd_is_set: 1 khi đã có mật khẩu hợp lệ
    // ------------------------------------------------------------------
    Password_Memory u_pwd_mem (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (write_en),
        .new_password (new_password),
        .pwd_out      (stored_password),
        .pwd_is_set   (pwd_is_set)
    );

    // ------------------------------------------------------------------
    // 3. Code_Checker
    //    So sánh input_buffer với stored_password khi en_compare pulse
    //    match_flag giữ kết quả cho đến khi clear_flag pulse
    // ------------------------------------------------------------------
    Code_Checker u_checker (
        .clk              (clk),
        .rst_n            (rst_n),
        .input_buffer     (input_buffer),
        .stored_password  (stored_password),
        .en_compare       (en_compare),
        .clear_flag       (clear_flag),
        .match_flag       (match_flag)
    );

    // ------------------------------------------------------------------
    // 4. Main_FSM
    //    Trung tâm điều phối: 8 state, xử lý logic khóa số
    // ------------------------------------------------------------------
    Main_FSM u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        // Keypad
        .key_valid       (key_valid),
        .key_code        (key_code),
        .is_function     (is_function),
        // Code_Checker
        .match_flag      (match_flag),
        .en_compare      (en_compare),
        .clear_flag      (clear_flag),
        .input_buffer    (input_buffer),
        // Password_Memory
        .pwd_is_set      (pwd_is_set),
        .write_en        (write_en),
        .new_password    (new_password),
        // LCD
        .lcd_line1       (lcd_line1),
        .lcd_line2       (lcd_line2),
        .lcd_update      (lcd_update),
        // Phần cứng
        .change_pass_btn (change_pass_btn),
        .unlock_led      (unlock_led),
        .error_leds      (error_leds),
        // Debug
        .state_out       (state_dbg)
    );

    // ------------------------------------------------------------------
    // 5. LCD_Driver
    //    Điều khiển LCD HD44780, nhận 2 dòng 128-bit ASCII từ Main_FSM
    // ------------------------------------------------------------------
    LCD_Driver u_lcd (
        .clk        (clk),
        .rst_n      (rst_n),
        .lcd_line1  (lcd_line1),
        .lcd_line2  (lcd_line2),
        .lcd_update (lcd_update),
        .LCD_DATA   (LCD_DATA),
        .LCD_EN     (LCD_EN),
        .LCD_RS     (LCD_RS),
        .LCD_RW     (LCD_RW),
        .LCD_ON     (LCD_ON)
    );

// =============================================================================
// KẾT NỐI LED PHẦN CỨNG
// =============================================================================

    assign LEDG = unlock_led;          // LEDG[0]: sáng xanh khi mở khóa
    assign LEDR = error_leds;          // LEDR[4:0]: sáng đỏ theo số lần sai

endmodule