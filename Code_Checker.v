module Code_Checker (
    input wire clk,             
    input wire cmp_en,           
    input wire [15:0] pwd_stored,
    input wire [15:0] pwd_entered,
    output reg is_match        
);

    always @(posedge clk) begin
        if (cmp_en) begin
            is_match <= (pwd_stored == pwd_entered);
        end else begin
            is_match <= 1'b0;
        end
    end

endmodule
