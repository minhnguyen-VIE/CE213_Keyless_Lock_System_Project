`include "Common_Params.v"

// =============================================================================
// Module  : Digital_Lock_Top2
// Ch?c n?ng: Top-level module khóa s? ? ph??ng án thay th? dùng SW + KEY
//            (khi không có bàn phím ma tr?n 4×4)
//
// So sánh v?i Digital_Lock_Top (b?n g?c):
//   THAY:  Keypad_Scanner (cols/rows, GPIO_0)
//   B?NG:  Switch_Input   (SW[9:0], KEY[3:1])
//   GI?:   Main_FSM, Password_Memory, Code_Checker, LCD_Driver (KHÔNG ??i)
//
// Pin mapping DE2:
//   CLOCK_50        ? clk
//   KEY[0]          ? rst_n         (active-low, gi? ?? reset)
//   KEY[1]          ? digit/ENT     (tùy SW[8])
//   KEY[2]          ? BACK          (xóa 1 s?)
//   KEY[3]          ? CLR           (xóa h?t)
//   SW[3:0]         ? Ch? s? nh?p (0000=0 .. 1001=9)
//   SW[8]           ? Ch? ??: 0=nh?p s?, 1=g?i ENT
//   SW[9]           ? Toggle HIDE (?n/hi?n m?t kh?u)
//   KEY[1] (dùng SW[7]) ? Nút ??i m?t kh?u (xem bên d??i)
//
// Nút ??i m?t kh?u:
//   Vì KEY[1..3] ?ã dùng h?t, dùng SW[7] làm "nút" ??i m?t kh?u:
//   G?t SW[7] lên (0?1) = t??ng ???ng nh?n change_pass_btn
//   Main_FSM dùng edge detector nên ch? trigger 1 l?n khi g?t
//
// H??ng d?n nh?p 1 l?n (ví d? nh?p m?t kh?u 123456):
//   1. SW[8]=0 (ch? ?? nh?p s?)
//   2. G?t SW[3:0]=0001, nh?n KEY[1] ? nh?p "1"
//   3. G?t SW[3:0]=0010, nh?n KEY[1] ? nh?p "2"
//   4. ... ti?p t?c ??n "6"
//   5. G?t SW[8]=1 (ch? ?? ENT), nh?n KEY[1] ? xác nh?n
// =============================================================================

module Digital_Lock_Top2 (
    // --- Clock & Reset ---
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,             // KEY[0]=rst_n, KEY[1..3]=ch?c n?ng

    // --- Switch input ---
    input  wire [9:0]  SW,              // SW[3:0]=digit, SW[7]=change_btn,
                                        // SW[8]=mode, SW[9]=HIDE

    // --- LCD HD44780 ---
    output wire [7:0]  LCD_DATA,
    output wire        LCD_EN,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_ON,

    // --- LED ngõ ra ---
    output wire        LEDG,            // LEDG[0]: m? khóa
    output wire [4:0]  LEDR,            // LEDR[4:0]: ??m l?i

    // --- LED tr?ng thái input (debug tr?c quan) ---
    output wire [3:0]  LEDG_SW,         // LEDG[4:1]: hi?n th? SW[3:0] ?ang g?t
    output wire        LEDG_MODE,       // LEDG[5]: SW[8] mode (0=digit, 1=ENT)
    output wire        LEDG_HIDE,       // LEDG[6]: SW[9] HIDE ?ang b?t

    // --- Debug ---
    output wire [2:0]  state_dbg
);

// =============================================================================
// TÍN HI?U N?I B?
// =============================================================================

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];

    // SW[7] làm change_pass_btn (edge detector trong Main_FSM x? lý)
    wire change_pass_btn = SW[7];

    // ?? Switch_Input ? Main_FSM ??
    wire        key_valid;
    wire [3:0]  key_code;
    wire        is_function;

    // ?? Main_FSM ? Code_Checker ??
    wire        en_compare;
    wire        clear_flag;
    wire [23:0] input_buffer;

    // ?? Main_FSM ? Password_Memory ??
    wire        write_en;
    wire [23:0] new_password;
    // read_en=1: luon cho doc; change_en=0: khong dung chuc nang reset rieng
    wire        pwd_read_en   = 1'b1;
    wire        pwd_change_en = 1'b0;

    // ?? Password_Memory ? Main_FSM & Code_Checker ??
    wire [23:0] stored_password;
    wire        pwd_is_set;

    // ?? Code_Checker ? Main_FSM ??
    wire        match_flag;

    // ?? Main_FSM ? LCD_Driver ??
    wire [127:0] lcd_line1;
    wire [127:0] lcd_line2;
    wire         lcd_update;

    // ?? Main_FSM ? LED ??
    wire        unlock_led;
    wire [4:0]  error_leds;

// =============================================================================
// INSTANTIATION
// =============================================================================

    // ------------------------------------------------------------------
    // 1. Switch_Input (thay th? Keypad_Scanner)
    // ------------------------------------------------------------------
    Switch_Input u_switch (
        .clk        (clk),
        .rst_n      (rst_n),
        .SW         (SW),
        .KEY        (KEY[3:1]),
        .key_code   (key_code),
        .key_valid  (key_valid),
        .is_function(is_function)
    );

    // ------------------------------------------------------------------
    // 2. Password_Memory (không ??i)
    // ------------------------------------------------------------------
    Password_Memory u_pwd_mem (
        .clk       (clk),
        .rst_n     (rst_n),
        .write_en  (write_en),
        .read_en   (pwd_read_en),
        .change_en (pwd_change_en),
        .pwd_in    (new_password),
        .pwd_out   (stored_password),
        .pwd_is_set(pwd_is_set)
    );

    // ------------------------------------------------------------------
    // 3. Code_Checker (không ??i)
    // ------------------------------------------------------------------
    Code_Checker u_checker (
        .clk             (clk),
        .rst_n           (rst_n),
        .input_buffer    (input_buffer),
        .stored_password (stored_password),
        .en_compare      (en_compare),
        .clear_flag      (clear_flag),
        .match_flag      (match_flag)
    );

    // ------------------------------------------------------------------
    // 4. Main_FSM (không ??i, ch? thay ngu?n key_valid/key_code)
    // ------------------------------------------------------------------
    Main_FSM u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .key_valid       (key_valid),
        .key_code        (key_code),
        .is_function     (is_function),
        .match_flag      (match_flag),
        .en_compare      (en_compare),
        .clear_flag      (clear_flag),
        .input_buffer    (input_buffer),
        .pwd_is_set      (pwd_is_set),
        .write_en        (write_en),
        .new_password    (new_password),
        .lcd_line1       (lcd_line1),
        .lcd_line2       (lcd_line2),
        .lcd_update      (lcd_update),
        .change_pass_btn (change_pass_btn),
        .unlock_led      (unlock_led),
        .error_leds      (error_leds),
        .state_out       (state_dbg)
    );

    // ------------------------------------------------------------------
    // 5. LCD_Driver (không ??i)
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
// K?T N?I LED
// =============================================================================

    assign LEDG      = unlock_led;
    assign LEDR      = error_leds;

    // LED debug tr?c quan ? giúp ki?m tra input không c?n LCD
    assign LEDG_SW   = SW[3:0];        // LEDG[4:1]: hi?n giá tr? SW ?ang g?t
    assign LEDG_MODE = SW[8];          // LEDG[5]: 0=nh?p s?, 1=ENT mode
    assign LEDG_HIDE = SW[9];          // LEDG[6]: HIDE ?ang b?t/t?t

endmodule