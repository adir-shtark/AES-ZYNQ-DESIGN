# Rebuild the Cora Z7-07S AES Vivado project from the sources in this repository.
#
# Usage, from this directory:
#   vivado -mode batch -source rebuild_project.tcl
#
# Options:
#   --force          overwrite an existing work/aes_design project
#   --bitstream      run implementation and write a bitstream into the XSA
#   --project_dir D  create the project in D instead of work/aes_design
#
# What gets recreated:
#   work/aes_design/aes_design.xpr
#   the design_1 block design (PS, AXI DMA, AES IP, interconnect, reset)
#   the design_1_wrapper top
#   any .xdc files placed in constraints/
#   hw_aes_design.xsa for Vitis
#
# The AES core is the packaged IP in IP/aes_top_level. Its Verilog is in rtl/.
# Application C sources for Vitis are in SW/aes_vitis/hello_aes_design/src.

set origin_dir [file dirname [file normalize [info script]]]

set force 0
set run_bitstream 0
set proj_name aes_design
set proj_dir [file normalize [file join $origin_dir work $proj_name]]

for {set i 0} {$i < [llength $::argv]} {incr i} {
  set arg [lindex $::argv $i]
  if {$arg eq "--force"} {
    set force 1
  } elseif {$arg eq "--bitstream"} {
    set run_bitstream 1
  } elseif {$arg eq "--project_dir"} {
    incr i
    set proj_dir [file normalize [lindex $::argv $i]]
  } else {
    puts "ERROR: Unknown argument '$arg'."
    exit 1
  }
}

set part xc7z007sclg400-1
set board_part digilentinc.com:cora-z7-07s:part0:1.1
set ip_repo [file normalize [file join $origin_dir IP aes_top_level]]

if {![file exists [file join $ip_repo component.xml]]} {
  puts "ERROR: AES IP repository not found at $ip_repo"
  exit 1
}

if {[file exists [file join $proj_dir ${proj_name}.xpr]] && !$force} {
  puts "ERROR: $proj_dir already contains ${proj_name}.xpr."
  puts "       Re-run with -tclargs --force to overwrite it."
  exit 1
}

file mkdir [file dirname $proj_dir]
if {$force && [file exists $proj_dir]} {
  file delete -force $proj_dir
}

create_project $proj_name $proj_dir -part $part
set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild

source [file join $origin_dir design_1_bd.tcl]

set bd_file [get_files design_1.bd]
make_wrapper -files $bd_file -top -import
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1

set xdc_files [glob -nocomplain -directory [file join $origin_dir constraints] *.xdc]
if {[llength $xdc_files] > 0} {
  add_files -fileset constrs_1 $xdc_files
}

generate_target all $bd_file

set xsa_file [file join $proj_dir hw_aes_design.xsa]
if {$run_bitstream} {
  launch_runs impl_1 -to_step write_bitstream -jobs 4
  wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "ERROR: Implementation did not finish successfully."
    exit 1
  }
  write_hw_platform -fixed -include_bit -force -file $xsa_file
} else {
  write_hw_platform -fixed -force -file $xsa_file
}

close_project
puts "INFO: Rebuilt Vivado project at $proj_dir"
puts "INFO: Hardware platform written to $xsa_file"
