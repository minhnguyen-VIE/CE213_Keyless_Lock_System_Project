library verilog;
use verilog.vl_types.all;
entity Code_Checker is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        input_buffer    : in     vl_logic_vector(23 downto 0);
        stored_password : in     vl_logic_vector(23 downto 0);
        en_compare      : in     vl_logic;
        clear_flag      : in     vl_logic;
        match_flag      : out    vl_logic
    );
end Code_Checker;
