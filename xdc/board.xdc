
# ---------------------------------------------------------------------------
# Pin definitions
# ---------------------------------------------------------------------------

 
#######################################
#  Clocks & system signals
#######################################

set_property -dict {PACKAGE_PIN  C4  IOSTANDARD LVDS_25} [ get_ports clk_100mhz_clk_p ]
set_property -dict {PACKAGE_PIN  C3  IOSTANDARD LVDS_25} [ get_ports clk_100mhz_clk_n ]
create_clock -period 10.000 -name sysclk100   [get_ports clk_100mhz_clk_p]
set_clock_groups -name group_sysclk100 -asynchronous -group [get_clocks sysclk100]



#===============================================================================
#                           <<<  QSFP 0  >>>
#===============================================================================
#
# Clock inputs for QSFP 0
#
set_property PACKAGE_PIN R33 [get_ports qsfp0_clk_clk_n]
set_property PACKAGE_PIN R32 [get_ports qsfp0_clk_clk_p]

#
# QSFP0 transciever connections
#
set_property PACKAGE_PIN L41 [get_ports qsfp0_gt_grx_p[0]]
set_property PACKAGE_PIN L42 [get_ports qsfp0_gt_grx_n[0]]
set_property PACKAGE_PIN K39 [get_ports qsfp0_gt_grx_p[1]]
set_property PACKAGE_PIN K40 [get_ports qsfp0_gt_grx_n[1]]
set_property PACKAGE_PIN J41 [get_ports qsfp0_gt_grx_p[2]]
set_property PACKAGE_PIN J42 [get_ports qsfp0_gt_grx_n[2]]
set_property PACKAGE_PIN H39 [get_ports qsfp0_gt_grx_p[3]]
set_property PACKAGE_PIN H40 [get_ports qsfp0_gt_grx_n[3]]

set_property PACKAGE_PIN M34 [get_ports qsfp0_gt_gtx_p[0]]
set_property PACKAGE_PIN M35 [get_ports qsfp0_gt_gtx_n[0]]
set_property PACKAGE_PIN L36 [get_ports qsfp0_gt_gtx_p[1]]
set_property PACKAGE_PIN L37 [get_ports qsfp0_gt_gtx_n[1]]
set_property PACKAGE_PIN K34 [get_ports qsfp0_gt_gtx_p[2]]
set_property PACKAGE_PIN K35 [get_ports qsfp0_gt_gtx_n[2]]
set_property PACKAGE_PIN J36 [get_ports qsfp0_gt_gtx_p[3]]
set_property PACKAGE_PIN J37 [get_ports qsfp0_gt_gtx_n[3]]
#===============================================================================



#===============================================================================
#                           <<<  QSFP 1  >>>
#===============================================================================
#
# Clock inputs for QSFP 1
#
set_property PACKAGE_PIN L33 [get_ports qsfp1_clk_clk_n]
set_property PACKAGE_PIN L32 [get_ports qsfp1_clk_clk_p]

#
# QSFP1 tranceiver connections
#
set_property PACKAGE_PIN G41 [get_ports qsfp1_gt_grx_p[0]]
set_property PACKAGE_PIN G42 [get_ports qsfp1_gt_grx_n[0]]
set_property PACKAGE_PIN F39 [get_ports qsfp1_gt_grx_p[1]]
set_property PACKAGE_PIN F40 [get_ports qsfp1_gt_grx_n[1]]
set_property PACKAGE_PIN E41 [get_ports qsfp1_gt_grx_p[2]]
set_property PACKAGE_PIN E42 [get_ports qsfp1_gt_grx_n[2]]
set_property PACKAGE_PIN D39 [get_ports qsfp1_gt_grx_p[3]]
set_property PACKAGE_PIN D40 [get_ports qsfp1_gt_grx_n[3]]

set_property PACKAGE_PIN H34 [get_ports qsfp1_gt_gtx_p[0]]
set_property PACKAGE_PIN H35 [get_ports qsfp1_gt_gtx_n[0]]
set_property PACKAGE_PIN G36 [get_ports qsfp1_gt_gtx_p[1]]
set_property PACKAGE_PIN G37 [get_ports qsfp1_gt_gtx_n[1]]
set_property PACKAGE_PIN F34 [get_ports qsfp1_gt_gtx_p[2]]
set_property PACKAGE_PIN F35 [get_ports qsfp1_gt_gtx_n[2]]
set_property PACKAGE_PIN E36 [get_ports qsfp1_gt_gtx_p[3]]
set_property PACKAGE_PIN E37 [get_ports qsfp1_gt_gtx_n[3]]
#===============================================================================




#######################################
#  Miscellaneous
#######################################

 set_property  -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports pb_rst_n] ;# PB_SW0
 set_property  -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports pb_req  ] ;# PB_SW1
#set_property  -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports pb_sw2  ] ;# PB_SW2



 set_property  -dict {PACKAGE_PIN B5  IOSTANDARD LVCMOS33}  [get_ports {    channel_up_0}]
 set_property  -dict {PACKAGE_PIN A5  IOSTANDARD LVCMOS33}  [get_ports {   led_heartbeat}]
 set_property  -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS33}  [get_ports {    channel_up_1}]
#set_property  -dict {PACKAGE_PIN C5  IOSTANDARD LVCMOS33}  [get_ports {    channel_up_1   }] ;# LED3
#set_property  -dict {PACKAGE_PIN C6  IOSTANDARD LVCMOS33}  [get_ports { sys_reset_out_1   }] ;# LED4
#set_property  -dict {PACKAGE_PIN C1  IOSTANDARD LVCMOS33}  [get_ports { c2c_link_status   }] ;# LED5
 set_property  -dict {PACKAGE_PIN D2  IOSTANDARD LVCMOS33}  [get_ports { GPIO_LED_tri_o[0] }] ;# LED6
 set_property  -dict {PACKAGE_PIN D3  IOSTANDARD LVCMOS33}  [get_ports { GPIO_LED_tri_o[1] }] ;# LED7
 set_property  -dict {PACKAGE_PIN D4  IOSTANDARD LVCMOS33}  [get_ports { GPIO_LED_tri_o[2] }] ;# LED8
 set_property  -dict {PACKAGE_PIN D1  IOSTANDARD LVCMOS33}  [get_ports { GPIO_LED_tri_o[3] }] ;# LED9



#set_property  -dict {PACKAGE_PIN B5  IOSTANDARD LVCMOS33}  [get_ports {  led[0]  }]
#set_property  -dict {PACKAGE_PIN A5  IOSTANDARD LVCMOS33}  [get_ports {  led[1]  }]
#set_property  -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS33}  [get_ports {  led[2]  }]
#set_property  -dict {PACKAGE_PIN C5  IOSTANDARD LVCMOS33}  [get_ports {  led[3]  }]
#set_property  -dict {PACKAGE_PIN C6  IOSTANDARD LVCMOS33}  [get_ports {  led[4]  }]
#set_property  -dict {PACKAGE_PIN C1  IOSTANDARD LVCMOS33}  [get_ports {  led[5]  }]
#set_property  -dict {PACKAGE_PIN D2  IOSTANDARD LVCMOS33}  [get_ports {  led[6]  }]
#set_property  -dict {PACKAGE_PIN D3  IOSTANDARD LVCMOS33}  [get_ports {  led[7]  }]
#set_property  -dict {PACKAGE_PIN D4  IOSTANDARD LVCMOS33}  [get_ports {  led[8]  }]
#set_property  -dict {PACKAGE_PIN D1  IOSTANDARD LVCMOS33}  [get_ports {  led[9]  }]


