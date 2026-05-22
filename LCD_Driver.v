`include "Common_Params.v"

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

    wire [7:0] initcode [0:7];
    assign initcode[0] = 8'h38;
    assign initcode[1] = 8'h38;
    assign initcode[2] = 8'h38;
    assign initcode[3] = 8'h38;
    assign initcode[4] = 8'h08;
    assign initcode[5] = 8'h01; // Lệnh Clear Display (Cần nhiều thời gian nhất)
    assign initcode[6] = 8'h06;
    assign initcode[7] = 8'h0C;

    // =========================================================================
    // ÉP XUNG LCD LÊN 10kHz (Tăng tốc độ phản hồi gấp 10 lần)
    // =========================================================================
    reg [14:0] clk_div;
    reg        lcd_clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 15'd0;
            lcd_clk <= 1'b0;
        // 50MHz / 5000 = 10kHz -> Chu kỳ 100 micro-giây (cực kỳ nhanh)
        end else if (clk_div == 15'd2499) begin 
            clk_div <= 15'd0;
            lcd_clk <= ~lcd_clk;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end

    // Toggle Synchronizer (Đồng bộ xung siêu nhạy)
    reg [127:0] buf_line1, buf_line2;
    reg         update_toggle_50;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_line1        <= {16{8'h20}};
            buf_line2        <= {16{8'h20}};
            update_toggle_50 <= 1'b0;
        end else if (lcd_update) begin
            buf_line1        <= lcd_line1;
            buf_line2        <= lcd_line2;
            update_toggle_50 <= ~update_toggle_50;
        end
    end

    reg sync1, sync2, sync3;
    always @(posedge lcd_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 1'b0; sync2 <= 1'b0; sync3 <= 1'b0;
        end else begin
            sync1 <= update_toggle_50;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end

    wire update_trigger = (sync2 ^ sync3);

    // =========================================================================
    // MÁY TRẠNG THÁI LCD
    // =========================================================================
    localparam [3:0]
        S_INIT      = 4'd0,   S_INIT_HOLD  = 4'd1,
        S_HOME      = 4'd2,   S_HOME_HOLD  = 4'd3,
        S_WRDATA1   = 4'd4,   S_WR1_HOLD   = 4'd5,
        S_LINE2     = 4'd6,   S_LINE2_HOLD = 4'd7,
        S_WRDATA2   = 4'd8,   S_WR2_HOLD   = 4'd9,
        S_DONE      = 4'd10;

    reg [3:0] state;
    reg [4:0] count;
    reg [4:0] delay_cnt; // Bộ đếm trễ chuyên dụng cho lúc khởi tạo
    reg       update_pending;

    function [7:0] get_byte;
        input [127:0] str;
        input [3:0]   idx;
        get_byte = str[127 - (idx * 8) -: 8];
    endfunction

    always @(posedge lcd_clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_INIT;
            count          <= 5'd0;
            delay_cnt      <= 5'd0;
            update_pending <= 1'b0;
            LCD_EN         <= 1'b0;
            LCD_RS         <= 1'b0;
            LCD_DATA       <= 8'h00;
        end else begin

            if (update_trigger)
                update_pending <= 1'b1;

            case (state)
                S_INIT: begin
                    LCD_RS   <= 1'b0;
                    LCD_EN   <= 1'b1;
                    LCD_DATA <= initcode[count[2:0]];
                    state    <= S_INIT_HOLD;
                end
                S_INIT_HOLD: begin
                    LCD_EN <= 1'b0;
                    // Màn hình chạy nhanh, nên phải bắt FSM đợi 20 chu kỳ (2ms) 
                    // để chip LCD kịp xóa màn hình ở bước Init
                    if (delay_cnt < 5'd20) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 5'd0;
                        if (count < 5'd7) begin
                            count <= count + 1'b1;
                            state <= S_INIT;
                        end else begin
                            count <= 5'd0;
                            state <= S_HOME;
                        end
                    end
                end
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
                        update_pending <= 1'b0;
                        state          <= S_DONE;
                    end
                end
                S_DONE: begin
                    LCD_EN <= 1'b0;
                    if (update_pending)
                        state <= S_HOME;
                end
                default: state <= S_INIT;
            endcase
        end
    end
endmodule