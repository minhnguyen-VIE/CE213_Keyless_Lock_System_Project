library verilog;
use verilog.vl_types.all;
entity Main_FSM is
    generic(
        LOCKOUT_CYCLES  : vl_logic_vector(31 downto 0) := (Hi1, Hi0, Hi1, Hi1, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1, Hi0, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi1, Hi0, Hi1, Hi1, Hi1, Hi1, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0, Hi0)
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        key_valid       : in     vl_logic;
        key_code        : in     vl_logic_vector(3 downto 0);
        is_function     : in     vl_logic;
        match_flag      : in     vl_logic;
        en_compare      : out    vl_logic;
        clear_flag      : out    vl_logic;
        input_buffer    : out    vl_logic_vector(23 downto 0);
        pwd_is_set      : in     vl_logic;
        write_en        : out    vl_logic;
        new_password    : out    vl_logic_vector(23 downto 0);
        lcd_line1       : out    vl_logic_vector(127 downto 0);
        lcd_line2       : out    vl_logic_vector(127 downto 0);
        lcd_update      : out    vl_logic;
        change_pass_btn : in     vl_logic;
        unlock_led      : out    vl_logic;
        error_leds      : out    vl_logic_vector(4 downto 0);
        state_out       : out    vl_logic_vector(2 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of LOCKOUT_CYCLES : constant is 2;
end Main_FSM;
