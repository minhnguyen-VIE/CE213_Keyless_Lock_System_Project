library verilog;
use verilog.vl_types.all;
entity Keypad_Scanner is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        cols            : in     vl_logic_vector(3 downto 0);
        rows            : out    vl_logic_vector(3 downto 0);
        key_code        : out    vl_logic_vector(3 downto 0);
        key_valid       : out    vl_logic;
        is_function     : out    vl_logic
    );
end Keypad_Scanner;
