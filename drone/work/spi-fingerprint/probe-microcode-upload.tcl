# probe-microcode-upload.tcl —— 按 BMI270 数据手册的初始化序列，手工上传 PX4 驱动里的配置块
# 判据：INTERNAL_STATUS(0x21) 从 0x00 变成 0x01 ⇒ 这确实是一颗能吃 BMI270 微码的兼容件
init
halt
echo "### MICROCODE-UPLOAD BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc xfer {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc drain {} { set n 0; while {$n < 16 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }; return $n }
proc csl {} { mww 0x58020418 0x00100000 }
proc csh {} { mww 0x58020418 0x00000010 }
proc rd {r} { csl; drain; xfer [expr {0x80|$r}]; set v [xfer 0x00]; csh; return $v }
proc wr {r val} { csl; drain; xfer [expr {$r & 0x7f}]; xfer $val; csh; return 0 }

echo [format {BEFORE 00=%02x 02=%02x 03=%02x 21=%02x 40=%02x 42=%02x 7d=%02x} [rd 0x00] [rd 0x02] [rd 0x03] [rd 0x21] [rd 0x40] [rd 0x42] [rd 0x7d]]
echo "-- 1. CMD(0x7E)=0xB6 软复位 --"
wr 0x7e 0xB6
sleep 20
echo [format {AFTER_SOFTRESET 00=%02x 02=%02x 03=%02x 21=%02x 40=%02x 42=%02x} [rd 0x00] [rd 0x02] [rd 0x03] [rd 0x21] [rd 0x40] [rd 0x42]]
echo "-- 2. PWR_CONF(0x7C)=0x00 --"
wr 0x7c 0x00
sleep 5
echo "-- 3. INIT_CTRL(0x59)=0x00 --"
wr 0x59 0x00
echo "-- 4. 突发写 329 字节配置块到 INIT_DATA(0x5E) --"
csl
drain
set n 0
foreach b {94 200 46 0 46 128 46 26 0 200 46 0 46 200 46 0 46 200 46 0 46 200 46 0 46 200 46 0 46 200 46 0 46 144 50 33 46 89 245 16 48 33 46 106 245 26 36 34 0 128 46 59 0 200 46 68 71 34 0 55 0 164 0 255 15 209 0 7 173 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 128 46 0 193 0 0 0 0 0 0 17 36 252 245 128 48 64 66 80 80 0 48 18 36 235 0 3 48 0 46 193 134 90 14 251 47 33 46 252 245 19 36 99 245 224 60 72 0 34 48 247 128 194 66 225 127 58 37 252 134 240 127 65 51 152 46 194 196 214 111 241 48 241 8 196 111 17 36 255 3 18 36 0 252 97 9 162 8 54 190 42 185 19 36 56 0 100 187 209 190 148 10 113 8 213 66 33 189 145 188 210 66 193 66 0 178 254 130 5 47 80 48 33 46 33 242 0 46 0 46 208 46 240 111 2 48 2 66 32 38 224 111 2 49 3 64 154 10 2 66 240 55 5 46 94 247 16 8 18 36 30 242 128 66 131 132 241 127 10 37 19 48 131 66 59 130 240 111 0 46 0 46 208 46 18 64 82 66 0 46 18 64 82 66 62 132 0 64 64 66 126 130 225 127 242 127 152 46 106 214 33 48 35 46 97 245 235 44 225 111} {
    xfer $b
    mem2array z 8 0x40013030 1
    incr n
}
csh
echo "BURST_WRITTEN $n bytes"
echo "-- 5. INIT_CTRL(0x59)=0x01 --"
wr 0x59 0x01
sleep 200
echo [format {AFTER_UPLOAD 21=%02x 00=%02x 02=%02x 03=%02x 40=%02x 42=%02x 7d=%02x 18=%02x%02x%02x} [rd 0x21] [rd 0x00] [rd 0x02] [rd 0x03] [rd 0x40] [rd 0x42] [rd 0x7d] [rd 0x18] [rd 0x19] [rd 0x1a]]
echo "-- 再读一次 INTERNAL_STATUS（BMI270 约定 message 在 bit0..3）--"
echo [format {INTERNAL_STATUS_RECHECK=%02x} [rd 0x21]]
mww 0x40013000 0x00001001
csh
echo "### MICROCODE-UPLOAD END ###"
resume
shutdown
