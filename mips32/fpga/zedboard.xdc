## ZedBoard (xc7z020clg484-1) constraints - used for the LED demo on a real board.
## The BTNC reset was not separately confirmed.
set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -period 10.000 -name sys_clk [get_ports clk100]
create_generated_clock -name core_clk -source [get_ports clk100] -divide_by 4 [get_pins div_cnt_reg[1]/Q]
## centre push button (BTNC)
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS18} [get_ports btn_reset]
## LEDs LD0..LD7
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
