`include "Common_Params.v"

module Keypad_Scanner(
    input wire clk, rst_n,
    input wire [3:0] cols,
    output reg [3:0] rows,
    output reg [3:0] key_code,
    output reg key_valid,
    output reg is_function
);

    // 1. Clock Divider (1kHz)
    reg [15:0] clk_div;
    wire scan_en = (clk_div == 16'd50000);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= 16'd0;
        else if (scan_en) clk_div <= 16'd0;
        else clk_div <= clk_div + 1'b1;
    end

    // 2. LOGIC QUï¿½T MA TR?N
    // --- KHAI Bï¿½O BI?N Cï¿½N THI?U ? ?ï¿½Y ---
    reg [1:0] row_index; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_index <= 2'd0;
            rows <= 4'b1110;
        end else if (scan_en && (cols == 4'b1111)) begin 
            row_index <= row_index + 1'b1;
            case (row_index + 1'b1) 
                2'd0: rows <= 4'b1110;
                2'd1: rows <= 4'b1101;
                2'd2: rows <= 4'b1011;
                2'd3: rows <= 4'b0111;
            endcase
        end
    end

    // 3. Debounce & Variables
    reg [19:0] debounce_cnt;
    reg [3:0] cols_last; // L?u tr?ng thái c?t c?a chu k? tr??c
    reg key_pressed_flag;
    reg [3:0] col_temp, row_temp;

    wire valid_column = (cols == 4'b1110 || cols == 4'b1101 || 
                         cols == 4'b1011 || cols == 4'b0111);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_cnt <= 20'd0;
            key_valid <= 1'b0;
            key_pressed_flag <= 1'b0;
            cols_last <= 4'b1111;
        end else begin
            // Nâng c?p: N?u c?t thay ??i so v?i chu k? tr??c -> Reset b? ??m
            if (cols != cols_last) begin
                debounce_cnt <= 20'd0;
            end 
            
            cols_last <= cols; // C?p nh?t tr?ng thái c?t

            if (cols != 4'b1111 && valid_column) begin 
                if (debounce_cnt < 20'd1000000) begin
                    debounce_cnt <= debounce_cnt + 1'b1;
                end else if (!key_pressed_flag) begin
                    key_valid <= 1'b1;
                    key_pressed_flag <= 1'b1;
                    col_temp <= cols;
                    row_temp <= rows;
                end else begin
                    key_valid <= 1'b0;
                end
            end else begin
                debounce_cnt <= 20'd0;
                key_pressed_flag <= 1'b0;
                key_valid <= 1'b0;
            end
        end
    end

    // 4. Decoder
    always @(*) begin
        is_function = 1'b0;
        case ({row_temp, col_temp})
            8'b1110_1110: key_code = `KEY_1;
            8'b1110_1101: key_code = `KEY_2;
            8'b1110_1011: key_code = `KEY_3;
            8'b1101_1110: key_code = `KEY_4;
            8'b1101_1101: key_code = `KEY_5;
            8'b1101_1011: key_code = `KEY_6;
            8'b1011_1110: key_code = `KEY_7;
            8'b1011_1101: key_code = `KEY_8;
            8'b1011_1011: key_code = `KEY_9;
            8'b0111_1101: key_code = `KEY_0;
            8'b0111_1110: begin key_code = `KEY_BACK; is_function = 1'b1; end
            8'b0111_1011: begin key_code = `KEY_ENT;  is_function = 1'b1; end
            8'b1110_0111: begin key_code = `KEY_CLR;  is_function = 1'b1; end
            8'b1101_0111: begin key_code = `KEY_HIDE; is_function = 1'b1; end
            default:      begin 
                key_code = `KEY_NONE; 
                is_function = 1'b1;
                if (key_pressed_flag) 
                    $display("[ERROR] Toa do khong hop le: R=%b C=%b", row_temp, col_temp);
            end
        endcase
    end
endmodule
