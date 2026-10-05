#---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
#---------------------------------------------------------------------------------------------------
# Creates the Versal Transceivers Wizard instance of the Physical adapter PA-1 (ofb_pa_gty) in the
# current Vivado project: one GTY quad, four duplex channels at 6.25 Gbit/s, 8B/10B in the
# transceiver, 32-bit user data (four symbols), comma alignment on the 7-bit comma at character 0
# of a word, receive elastic buffer with clock correction on the SpaceFibre SKIP word.
#
# Usage (Vivado Tcl):
#   source hdl/ofb_pa_gty/tcl/ofb_gtw.tcl
#   ofb_gtw_create ofb_gtw 156.25
#
# Documentation: hdl/ofb_pa_gty/docs/architecture.md
#---------------------------------------------------------------------------------------------------

# Transceiver settings of one line rate (LR0). Keys not listed keep the wizard defaults.
# The combined clock correction fields RX_CC_K (one K flag per character, sequence 1 in bits 3:0) and RX_CC_VAL
# (10 bits per character, the value in bits 7:0, sequence 1 in the lower 40 bits) are not derived from the
# per-character keys when the settings are set by Tcl; the format follows the Gigabit Ethernet preset of the wizard.
proc ofb_gtw_lr0 {refclk_mhz} {
    set rc [format %.12f $refclk_mhz]
    return [list \
        GT_DIRECTION DUPLEX GT_TYPE GTY PRESET None INTERNAL_PRESET None \
        TX_LINE_RATE 6.25 RX_LINE_RATE 6.25 \
        TX_PLL_TYPE LCPLL RX_PLL_TYPE LCPLL \
        TX_REFCLK_FREQUENCY $refclk_mhz RX_REFCLK_FREQUENCY $refclk_mhz \
        TX_ACTUAL_REFCLK_FREQUENCY $rc RX_ACTUAL_REFCLK_FREQUENCY $rc \
        TX_REFCLK_SOURCE R0 RX_REFCLK_SOURCE R0 \
        TX_DATA_ENCODING 8B10B RX_DATA_DECODING 8B10B \
        TX_USER_DATA_WIDTH 32 TX_INT_DATA_WIDTH 40 RX_USER_DATA_WIDTH 32 RX_INT_DATA_WIDTH 40 \
        TX_BUFFER_MODE 1 RX_BUFFER_MODE 1 \
        TX_OUTCLK_SOURCE TXOUTCLKPMA RX_OUTCLK_SOURCE RXOUTCLKPMA \
        RX_COMMA_PRESET NONE RX_COMMA_P_ENABLE true RX_COMMA_M_ENABLE true \
        RX_COMMA_P_VAL 0101111100 RX_COMMA_M_VAL 1010000011 RX_COMMA_MASK 0001111111 \
        RX_COMMA_ALIGN_WORD 4 RX_COMMA_DOUBLE_ENABLE false RX_COMMA_SHOW_REALIGN_ENABLE true \
        RX_COMMA_VALID_ONLY 0 RX_SLIDE_MODE OFF \
        RX_CC_NUM_SEQ 1 RX_CC_LEN_SEQ 4 RX_CC_PERIODICITY 5000 RX_CC_KEEP_IDLE DISABLE \
        RX_CC_PRECEDENCE ENABLE RX_CC_REPEAT_WAIT 0 \
        RX_CC_VAL_0_0 11111100 RX_CC_K_0_0 true RX_CC_DISP_0_0 false RX_CC_MASK_0_0 false \
        RX_CC_VAL_0_1 11001110 RX_CC_K_0_1 false RX_CC_DISP_0_1 false RX_CC_MASK_0_1 false \
        RX_CC_VAL_0_2 01111111 RX_CC_K_0_2 false RX_CC_DISP_0_2 false RX_CC_MASK_0_2 false \
        RX_CC_VAL_0_3 01111111 RX_CC_K_0_3 false RX_CC_DISP_0_3 false RX_CC_MASK_0_3 false \
        RX_CC_K 00000001 RX_CC_DISP 00000000 RX_CC_MASK 00000000 \
        RX_CC_VAL [string repeat 0 40]0001111111000111111100110011100011111100 \
        RX_CB_NUM_SEQ 0 \
        RX_EQ_MODE AUTO RX_COUPLING AC RX_SSC_PPM 0 RX_PPM_OFFSET 200 \
    ]
}

# Optional ports of every channel: 8B/10B control and status, polarity, CDR hold, electrical idle,
# alignment and buffer status
proc ofb_gtw_ports {} {
    return {ch_txctrl0 ch_txctrl1 ch_txctrl2 ch_rxctrl0 ch_rxctrl1 ch_rxctrl2 ch_rxctrl3
            ch_txpolarity ch_rxpolarity ch_rxcdrhold ch_txelecidle ch_rxelecidle
            ch_rxbyteisaligned ch_rxbyterealign ch_rxbufstatus ch_txbufstatus ch_rxclkcorcnt
            ch_rxresetdone ch_txresetdone}
}

proc ofb_gtw_create {name refclk_mhz} {
    create_ip -vlnv [lindex [get_ipdefs -all xilinx.com:ip:gtwiz_versal:*] end] -module_name $name
    set ip [get_ips $name]
    # LR0: defaults of the wizard, overridden by the OpenFibre settings
    set lr0 [dict create]
    foreach {k v} [ofb_gtw_lr0 $refclk_mhz] { dict set lr0 $k $v }
    set settings [list GT_TYPE GTY GT_DIRECTION DUPLEX LR0_SETTINGS $lr0]
    for {set i 1} {$i < 16} {incr i} { lappend settings LR${i}_SETTINGS {NA NA} }
    set_property CONFIG.INTF0_GT_SETTINGS $settings $ip
    # Optional ports: INTF0_OPTIONAL_PORTS takes the dictionary of all ports (INTF0_TXRX_OPTIONAL_PORTS)
    # with the wanted ones enabled
    set ports [get_property CONFIG.INTF0_TXRX_OPTIONAL_PORTS $ip]
    foreach p [ofb_gtw_ports] {
        if {![dict exists $ports $p]} { error "ofb_gtw: unknown optional port $p" }
        dict set ports $p true
    }
    set_property CONFIG.INTF0_OPTIONAL_PORTS $ports $ip
    set got [get_property CONFIG.INTF0_OPTIONAL_PORTS $ip]
    foreach p [ofb_gtw_ports] {
        if {[dict get $got $p] ne "true"} { error "ofb_gtw: optional port $p not enabled" }
    }
    return $ip
}
