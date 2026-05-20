library verilog;
use verilog.vl_types.all;
entity LCD_Driver is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        lcd_line1       : in     vl_logic_vector(127 downto 0);
        lcd_line2       : in     vl_logic_vector(127 downto 0);
        lcd_update      : in     vl_logic;
        LCD_DATA        : out    vl_logic_vector(7 downto 0);
        LCD_EN          : out    vl_logic;
        LCD_RS          : out    vl_logic;
        LCD_RW          : out    vl_logic;
        LCD_ON          : out    vl_logic
    );
end LCD_Driver;
