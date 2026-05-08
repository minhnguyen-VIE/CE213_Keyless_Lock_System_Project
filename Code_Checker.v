module Code_Checker(
    input wire clk,
    input wire rst_n,
    input wire [23:0] input_buffer,    // D? li?u ng??i dùng ?ã nh?p
    input wire [23:0] stored_password, // M?t kh?u g?c
    input wire en_compare,             // L?nh kích ho?t so sánh
    input wire clear_flag,             // L?nh xóa tr?ng thái
    
    output reg match_flag              // C? báo kh?p m?t kh?u
);

    // -------------------------------------------------------
    // LÕI T? H?P (COMBINATIONAL CORE)
    // -------------------------------------------------------
    wire is_matched = (input_buffer == stored_password);

    // -------------------------------------------------------
    // V? TU?N T? (SEQUENTIAL WRAPPER)
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin // <--- Chú ý t? khóa 'begin' ? ?ây
        if (!rst_n) begin
            match_flag <= 1'b0;
        end else begin
            // ?u tiên 1: Xóa tr?ng thái
            if (clear_flag) begin
                match_flag <= 1'b0;
            end 
            // ?u tiên 2: Th?c hi?n so sánh khi có l?nh
            else if (en_compare) begin
                match_flag <= is_matched;
            end
        end
    end

endmodule