module Code_Checker(
    input wire clk,
    input wire rst_n,
    input wire [23:0] input_buffer,    // D? li?u ng??i d�ng ?� nh?p
    input wire [23:0] stored_password, // M?t kh?u g?c
    input wire en_compare,             // L?nh k�ch ho?t so s�nh
    input wire clear_flag,             // L?nh x�a tr?ng th�i
    
    output reg match_flag              // C? b�o kh?p m?t kh?u
);

    // -------------------------------------------------------
    // L�I T? H?P (COMBINATIONAL CORE)
    // -------------------------------------------------------
    wire is_matched = (input_buffer == stored_password);

    // -------------------------------------------------------
    // V? TU?N T? (SEQUENTIAL WRAPPER)
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin // <--- Ch� � t? kh�a 'begin' ? ?�y
        if (!rst_n) begin
            match_flag <= 1'b0;
        end else begin
            // ?u ti�n 1: X�a tr?ng th�i
            if (clear_flag) begin
                match_flag <= 1'b0;
            end 
            // ?u ti�n 2: Th?c hi?n so s�nh khi c� l?nh
            else if (en_compare) begin
                match_flag <= is_matched;
            end
        end
    end
endmodule