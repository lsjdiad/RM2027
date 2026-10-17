init
reset run
for {set i 0} {$i < 30} {incr i} {
    after 1000
    halt
    dump_image /tmp/cap_$i.bin 0x2400a444 0x1000
    resume
}
shutdown
