library verilog;
use verilog.vl_types.all;
entity Digital_Lock_Top2 is
    port(
        CLOCK_50        : in     vl_logic;
        KEY             : in     vl_logic_vector(3 downto 0);
        SW              : in     vl_logic_vector(9 downto 0);
        LCD_DATA        : out    vl_logic_vector(7 downto 0);
        LCD_EN          : out    vl_logic;
        LCD_RS          : out    vl_logic;
        LCD_RW          : out    vl_logic;
        LCD_ON          : out    vl_logic;
        LEDG            : out    vl_logic;
        LEDR            : out    vl_logic_vector(4 downto 0);
        LEDG_SW         : out    vl_logic_vector(3 downto 0);
        LEDG_MODE       : out    vl_logic;
        LEDG_HIDE       : out    vl_logic;
        state_dbg       : out    vl_logic_vector(2 downto 0)
    );
end Digital_Lock_Top2;
