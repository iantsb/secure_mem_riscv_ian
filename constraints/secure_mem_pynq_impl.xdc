create_clock -name clock -period 12.000 [get_ports clock]

set_false_path -from [get_ports reset]
set_false_path -from [get_ports {start_i write_i cfg_i sw_i[*]}]