`include "Common_Params.v"

module Input_Buffer (
    input wire clk,
    input wire rst_n,
    
    // Tín hiệu từ Keypad_Scanner
    input wire [3:0] key_code,
    input wire key_valid,
    input wire is_function,
    
    // Tín hiệu từ Main_FSM (Điều khiển)
    input wire clear_req,        // Lệnh xóa buffer từ FSM (khi mở cửa xong hoặc khóa lại)
    
    // Ngõ ra
    output reg [23:0] buffer_data, // Dữ liệu 6 số đã nhập
    output reg [2:0] digit_count,  // Số lượng phím đã nhập (0 đến 6)
    output reg enter_pressed       // Cờ báo người dùng đã bấm Enter
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_data <= 24'h000000;
            digit_count <= 3'd0;
            enter_pressed <= 1'b0;
        end else begin
            // 1. Ưu tiên cao nhất: Lệnh xóa từ hệ thống trung tâm
            if (clear_req) begin
                buffer_data <= 24'h000000;
                digit_count <= 3'd0;
                enter_pressed <= 1'b0;
            end 
            // 2. Xử lý khi có phím mới được bấm
            else if (key_valid) begin
                
                // Mặc định hạ cờ enter xuống ở mỗi chu kỳ nhận phím mới
                enter_pressed <= 1'b0; 

                // Trường hợp A: Phím CHỨC NĂNG
                if (is_function) begin
                    case (key_code)
                        `KEY_CLR: begin // Xóa toàn bộ
                            buffer_data <= 24'h000000;
                            digit_count <= 3'd0;
                        end
                        
                        `KEY_BACK: begin // Xóa lùi 1 ký tự
                            if (digit_count > 0) begin
                                // Dịch phải 4 bit, điền 0 vào đầu
                                buffer_data <= {4'h0, buffer_data[23:4]};
                                digit_count <= digit_count - 1'b1;
                            end
                        end
                        
                        `KEY_ENT: begin // Bấm Enter xác nhận
                            if (digit_count == 3'd6) begin
                                enter_pressed <= 1'b1; // Chỉ phát lệnh khi đã nhập đủ 6 số
                            end
                        end
                    endcase
                end 
                // Trường hợp B: Phím SỐ (0-9)
                else begin
                    // Chỉ cho phép nhập thêm nếu chưa đầy 6 số
                    if (digit_count < 3'd6) begin
                        // Dịch trái 4 bit, đưa số mới vào đuôi
                        buffer_data <= {buffer_data[19:0], key_code};
                        digit_count <= digit_count + 1'b1;
                    end
                end
            end else begin
                // Đảm bảo cờ Enter chỉ là 1 xung (Pulse)
                enter_pressed <= 1'b0; 
            end
        end
    end

endmodule