source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 500
init
halt
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<300} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}
    foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { set o [seq [list [expr {$reg|0x80}] 0x00]]; return [lindex $o 1] }
proc wr {reg val} { seq [list $reg $val] }
wr 0x7D 0x0E
after 20
echo "cand  imm  after200ms   说明"
foreach v {0xCC 0xAC 0x8C 0xEC 0xED 0xAD 0xAB 0xEE 0xA9} {
    wr 0x42 $v
    set a [rd 0x42]
    after 200
    set b [rd 0x42]
    set mark "KEEP"
    if {$a != $b} { set mark "**回落**" }
    if {$b != $v} { append mark " (落成 [format %02X $b])" }
    echo [format "%02X    %02X   %02X        %s" $v $a $b $mark]
}
resume
shutdown
