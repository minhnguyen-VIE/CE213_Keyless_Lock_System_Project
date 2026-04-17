`include "Common_Params.v"

module Keypad_Scanner(
    input wire clk,              // Xung clock 50MHz từ Kit DE2
    input wire rst_n,            // Reset mức thấp (KEY0)
    input wire [3:0] cols,       // 4 chân Cột (Input từ Keypad)
    output reg [3:0] rows,       // 4 chân Hàng (Output tới Keypad)
    output reg [3:0] key_code,   // Mã 4-bit của phím (0-9, A, B, C...)
    output reg key_valid,        // Xung báo hiệu đã nhấn phím xong
    output reg is_function       // Phân loại: 0 (Số), 1 (Chức năng)
);

    //-------------------------------------------------------
    // 1. BỘ CHIA TẦN SỐ (CLOCK DIVIDER)
    // Tạo xung quét tần số ~1kHz (1ms) để tránh nhiễu cao tần
    //-------------------------------------------------------
    reg [15:0] clk_div;
    wire scan_en = (clk_div == 16'd50000); // 50MHz / 50000 = 1kHz

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= 16'd0;
        else if (scan_en) clk_div <= 16'd0;
        else clk_div <= clk_div + 1'b1;
    end
	 
	 //-------------------------------------------------------
    // 2. LOGIC QUÉT MA TRẬN (MATRIX SCANNING)
    // Dịch bit '0' qua từng hàng mỗi 1ms
    //-------------------------------------------------------

	 reg [1:0] row_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_index <= 2'd0;
            rows <= 4'b1110; // Bắt đầu quét hàng 0 (mức thấp active)
        end else if (scan_en) begin
            row_index <= row_index + 1'b1;
            case (row_index)
                2'd0: rows <= 4'b1101; // Quét Hàng 1
                2'd1: rows <= 4'b1011; // Quét Hàng 2
                2'd2: rows <= 4'b0111; // Quét Hàng 3
                2'd3: rows <= 4'b1110; // Quay lại Hàng 0
            endcase
        end
    end
	 
	 //-------------------------------------------------------
    // 3. KHỬ NHIỄU (DEBOUNCE) & PHÁT HIỆN NHẤN PHÍM
    // Chỉ xác nhận khi phím giữ ổn định trong 20ms
    //-------------------------------------------------------
    reg [19:0] debounce_cnt;
    reg [3:0] col_temp;
    reg [3:0] row_temp;
    reg key_pressed_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_cnt <= 20'd0;
            key_valid <= 1'b0;
            key_pressed_flag <= 1'b0;
        end else begin
            // Nếu có bất kỳ cột nào xuống mức 0 (có nhấn phím)
            if (cols != 4'b1111) begin
                if (debounce_cnt < 20'd1000000) begin // Đợi 20ms (tại 50MHz)
                    debounce_cnt <= debounce_cnt + 1'b1;
                    key_valid <= 1'b0;
                end else if (!key_pressed_flag) begin
                    // Xác nhận nhấn phím thành công
                    key_valid <= 1'b1; 
                    key_pressed_flag <= 1'b1;
                    col_temp <= cols; // Lưu lại trạng thái cột
                    row_temp <= rows; // Lưu lại trạng thái hàng
                end else begin
                    key_valid <= 1'b0;
                end
            end else begin
                // Người dùng đã thả phím
                debounce_cnt <= 20'd0;
                key_pressed_flag <= 1'b0;
                key_valid <= 1'b0;
            end
        end
    end
	 
	 //-------------------------------------------------------
    // 4. BỘ GIẢI MÃ (DECODER / KEY MAPPING)
    // Ánh xạ tọa độ Hàng/Cột sang chức năng cụ thể
    //-------------------------------------------------------
    always @(*) begin
        is_function = 1'b0; // Mặc định là phím số để code ngắn gọn hơn
        case ({row_temp, col_temp})
            // --- CÁC PHÍM SỐ (0-9) ---
            8'b1110_1110: key_code = `KEY_1; // Số 1
            8'b1110_1101: key_code = `KEY_2; // Số 2
            8'b1110_1011: key_code = `KEY_3; // Số 3
            8'b1101_1110: key_code = `KEY_4; // Số 4
            8'b1101_1101: key_code = `KEY_5; // Số 5
            8'b1101_1011: key_code = `KEY_6; // Số 6
            8'b1011_1110: key_code = `KEY_7; // Số 7
            8'b1011_1101: key_code = `KEY_8; // Số 8
            8'b1011_1011: key_code = `KEY_9; // Số 9
            8'b0111_1101: key_code = `KEY_0; // Số 0

            // --- CÁC PHÍM CHỨC NĂNG (is_function = 1) ---
            8'b0111_1110: begin key_code = `KEY_BACK; is_function = 1'b1; end
            8'b0111_1011: begin key_code = `KEY_ENT;  is_function = 1'b1; end
            8'b1110_0111: begin key_code = `KEY_CLR;  is_function = 1'b1; end
            8'b1101_0111: begin key_code = `KEY_HIDE; is_function = 1'b1; end

            default:      begin key_code = `KEY_NONE; is_function = 1'b1; end
        endcase
    end

endmodule