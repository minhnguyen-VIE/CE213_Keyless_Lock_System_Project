library verilog;
use verilog.vl_types.all;
entity Top_Test_Keypad is
    port(
        CLOCK_50        : in     vl_logic;
        KEY             : in     vl_logic_vector(0 downto 0);
        GPIO_0          : inout  vl_logic_vector(35 downto 0);
        HEX0            : out    vl_logic_vector(6 downto 0);
        LEDR            : out    vl_logic_vector(3 downto 0);
        LEDR_17         : out    vl_logic
    );
end Top_Test_Keypad;
