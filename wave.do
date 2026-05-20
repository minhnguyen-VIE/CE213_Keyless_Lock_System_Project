onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {--- SYSTEM ---}
add wave -noupdate /tb_Digital_Lock_Top2/clk
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_switch/rst_n
add wave -noupdate /tb_Digital_Lock_Top2/KEY
add wave -noupdate /tb_Digital_Lock_Top2/SW
add wave -noupdate -divider {--- INPUTS ---}
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_switch/key_code
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_switch/key_valid
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_switch/is_function
add wave -noupdate -divider {--- FSM ---}
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_fsm/input_buffer
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_fsm/state
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_fsm/digit_count
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_pwd_mem/write_en
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_pwd_mem/password_storage
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_checker/en_compare
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_checker/match_flag
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_checker/input_buffer
add wave -noupdate /tb_Digital_Lock_Top2/dut/u_checker/stored_password
add wave -noupdate -divider {--- OUTPUTS ---}
add wave -noupdate /tb_Digital_Lock_Top2/LEDG
add wave -noupdate /tb_Digital_Lock_Top2/LEDR
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {572 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 288
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {759 ps}
