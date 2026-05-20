library verilog;
use verilog.vl_types.all;
entity Switch_Input is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        SW              : in     vl_logic_vector(9 downto 0);
        KEY             : in     vl_logic_vector(3 downto 1);
        key_code        : out    vl_logic_vector(3 downto 0);
        key_valid       : out    vl_logic;
        is_function     : out    vl_logic
    );
end Switch_Input;
