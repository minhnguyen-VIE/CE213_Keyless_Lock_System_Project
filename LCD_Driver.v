`include "Common_Params.v"

// =============================================================================
// Module  : LCD_Driver
// Chức năng: Điều khiển LCD 16x2 (HD44780) trên KIT DE2 Altera
// Clock   : 50 MHz (clk)
// Reset   : Bất đồng bộ, tích cực mức thấp (rst_n)
// Cú pháp : Verilog-2001 thuần — không dùng SystemVerilog
//           (tương thích Quartus II 13.0 SP1 + Cyclone II)
//
// Ngõ vào : lcd_line1 [127:0]  -- 16 ký tự ASCII dòng 1 (MSB = ký tự trái nhất)
//           lcd_line2 [127:0]  -- 16 ký tự ASCII dòng 2
//           lcd_update         -- Pulse 1 cycle từ Main_FSM: yêu cầu refresh
// Ngõ ra  : LCD_DATA  [7:0]    -- Bus dữ liệu 8-bit
//           LCD_EN             -- Enable strobe
//           LCD_RS             -- 0=Instruction / 1=Data
//           LCD_RW             -- Cố định 0 (Write-only)
//           LCD_ON             -- Cố định 1 (Bật màn hình)
//
// Sơ đồ refresh (không re-INIT sau lần đầu, tránh nhấp nháy):
//   INIT(×8) → HOME(0x80) → WRDATA1(×16) → LINE2(0xC0) → WRDATA2(×16) → DONE
//   DONE ──(update_pending)──► HOME  (chỉ ghi lại data, skip INIT)
//
// Fix so với bản cũ:
//   1. INIT_SEQ dùng wire+assign thay vì localparam array (Verilog-2001 safe)
//   2. update_pending chỉ có 1 always block driver duy nhất
//   3. lcd_clk toggle đúng tần số 1 kHz (50MHz / 25000 / 2)
// =============================================================================

module LCD_Driver (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] lcd_line1,
    input  wire [127:0] lcd_line2,
    input  wire         lcd_update,
    output reg  [7:0]   LCD_DATA,
    output reg          LCD_EN,
    output reg          LCD_RS,
    output wire         LCD_RW,
    output wire         LCD_ON
);

    assign LCD_RW = 1'b0;
    assign LCD_ON = 1'b1;

    // -------------------------------------------------------------------------
    // INIT SEQUENCE — Verilog-2001: dùng wire array + assign riêng từng phần tử
    // Theo datasheet HD44780, trang 45 (Sparkfun PDF)
    // -------------------------------------------------------------------------
    wire [7:0] initcode [0:7];
    assign initcode[0] = 8'h38;  // Function Set ×4: 8-bit, 2 lines, 5x8
    assign initcode[1] = 8'h38;
    assign initcode[2] = 8'h38;
    assign initcode[3] = 8'h38;
    assign initcode[4] = 8'h08;  // Display OFF
    assign initcode[5] = 8'h01;  // Clear Display (cần ~1.64ms, 1 cycle @1kHz đủ)
    assign initcode[6] = 8'h06;  // Entry Mode: increment, no shift
    assign initcode[7] = 8'h0C;  // Display ON, cursor OFF, blink OFF

    // -------------------------------------------------------------------------
    // CLOCK DIVIDER — 50MHz → 1kHz
    // Toggle lcd_clk mỗi 25000 cycles → posedge lcd_clk = 1ms
    // -------------------------------------------------------------------------
    reg [14:0] clk_div;
    reg        lcd_clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 15'd0;
            lcd_clk <= 1'b0;
        end else if (clk_div == 15'd24999) begin
            clk_div <= 15'd0;
            lcd_clk <= ~lcd_clk;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // BUFFER LATCH — 50MHz domain
    // Chụp ảnh lcd_line1/line2 khi có lcd_update, tránh glitch khi
    // Main_FSM thay đổi data trong khi LCD FSM đang ghi giữa chừng
    // -------------------------------------------------------------------------
    reg [127:0] buf_line1, buf_line2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_line1 <= {16{8'h20}};   // 16 spaces
            buf_line2 <= {16{8'h20}};
        end else if (lcd_update) begin
            buf_line1 <= lcd_line1;
            buf_line2 <= lcd_line2;
        end
    end

    // -------------------------------------------------------------------------
    // LCD FSM — chạy trên lcd_clk (1kHz)
    // State encoding
    // -------------------------------------------------------------------------
    localparam [3:0]
        S_INIT      = 4'd0,   S_INIT_HOLD  = 4'd1,
        S_HOME      = 4'd2,   S_HOME_HOLD  = 4'd3,
        S_WRDATA1   = 4'd4,   S_WR1_HOLD   = 4'd5,
        S_LINE2     = 4'd6,   S_LINE2_HOLD = 4'd7,
        S_WRDATA2   = 4'd8,   S_WR2_HOLD   = 4'd9,
        S_DONE      = 4'd10;

    reg [3:0] state;
    reg [4:0] count;
    reg       update_pending;

    // Hàm lấy byte thứ idx (0=trái nhất) từ chuỗi 128-bit
    // Byte 0 = bits[127:120], Byte 1 = bits[119:112], ...
    function [7:0] get_byte;
        input [127:0] str;
        input [3:0]   idx;
        get_byte = str[127 - (idx * 8) -: 8];
    endfunction

    // -------------------------------------------------------------------------
    // LCD FSM — 1 always block duy nhất, SINGLE DRIVER cho mọi reg
    // Bao gồm cả update_pending để tránh multiple driver
    // -------------------------------------------------------------------------
    always @(posedge lcd_clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_INIT;
            count          <= 5'd0;
            update_pending <= 1'b0;
            LCD_EN         <= 1'b0;
            LCD_RS         <= 1'b0;
            LCD_DATA       <= 8'h00;
        end else begin

            // Detect lcd_update (từ domain 50MHz, chấp nhận 1-cycle latency)
            // update_pending chỉ set ở đây, clear ở cuối S_WR2_HOLD
            if (lcd_update)
                update_pending <= 1'b1;

            case (state)

                // ----- INIT: Gửi 8 lệnh khởi tạo chip -----
                S_INIT: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= initcode[count[2:0]];
                    state    <= S_INIT_HOLD;
                end
                S_INIT_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd7) begin
                        count <= count + 1'b1;
                        state <= S_INIT;
                    end else begin
                        count <= 5'd0;
                        state <= S_HOME;
                    end
                end

                // ----- HOME: Set DDRAM addr = 0x00 (đầu dòng 1) -----
                S_HOME: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= 8'h80;
                    state    <= S_HOME_HOLD;
                end
                S_HOME_HOLD: begin
                    LCD_EN <= 1'b0;
                    count  <= 5'd0;
                    state  <= S_WRDATA1;
                end

                // ----- WRDATA1: Ghi 16 ký tự dòng 1 -----
                S_WRDATA1: begin
                    LCD_RS   <= 1'b1;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= get_byte(buf_line1, count[3:0]);
                    state    <= S_WR1_HOLD;
                end
                S_WR1_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd15) begin
                        count <= count + 1'b1;
                        state <= S_WRDATA1;
                    end else begin
                        count <= 5'd0;
                        state <= S_LINE2;
                    end
                end

                // ----- LINE2: Set DDRAM addr = 0x40 (đầu dòng 2) -----
                S_LINE2: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= 8'hC0;
                    state    <= S_LINE2_HOLD;
                end
                S_LINE2_HOLD: begin
                    LCD_EN <= 1'b0;
                    count  <= 5'd0;
                    state  <= S_WRDATA2;
                end

                // ----- WRDATA2: Ghi 16 ký tự dòng 2 -----
                S_WRDATA2: begin
                    LCD_RS   <= 1'b1;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= get_byte(buf_line2, count[3:0]);
                    state    <= S_WR2_HOLD;
                end
                S_WR2_HOLD: begin
                    LCD_EN <= 1'b0;
                    if (count < 5'd15) begin
                        count <= count + 1'b1;
                        state <= S_WRDATA2;
                    end else begin
                        count          <= 5'd0;
                        update_pending <= 1'b0;  // Clear SAU khi ghi xong
                        state          <= S_DONE;
                    end
                end

                // ----- DONE: Chờ yêu cầu refresh mới -----
                // Không re-INIT (tránh nhấp nháy), chỉ quay về HOME
                S_DONE: begin
                    LCD_EN <= 1'b0;
                    if (update_pending)
                        state <= S_HOME;
                    // update_pending đã được set trong nhánh if(lcd_update) ở trên
                end

                default: state <= S_INIT;

            endcase
        end
    end

endmodule