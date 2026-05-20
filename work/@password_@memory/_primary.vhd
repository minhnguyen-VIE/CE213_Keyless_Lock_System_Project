library verilog;
use verilog.vl_types.all;
entity Password_Memory is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        write_en        : in     vl_logic;
        read_en         : in     vl_logic;
        change_en       : in     vl_logic;
        pwd_in          : in     vl_logic_vector(23 downto 0);
        pwd_out         : out    vl_logic_vector(23 downto 0);
        pwd_is_set      : out    vl_logic
    );
end Password_Memory;
