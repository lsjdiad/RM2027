# BMI270 官方寄存器图（逐行摘录，来源可复现）

来源：Bosch 官方驱动 BMI270_SensorAPI 的头文件
URL : https://raw.githubusercontent.com/boschsensortec/BMI270_SensorAPI/master/bmi2_defs.h
取法：grep 'define BMI2_.*_ADDR' bmi2_defs.h
抓取：2026-09-30；镜像：https://ghproxy.net/ 前缀（境外直连失败时用）

# 另见 PX4 自带驱动（地址一致）：src/drivers/imu/bosch/bmi270/Bosch_BMI270_registers.hpp

| addr | BMI270 名称 |
|---|---|
| 0x00 | CHIP_ID |
| 0x03 | STATUS |
| 0x04 | AUX_X_LSB |
| 0x0C | ACC_X_LSB |
| 0x12 | GYR_X_LSB |
| 0x18 | SENSORTIME |
| 0x1B | EVENT |
| 0x1C | INT_STATUS_0 |
| 0x1D | INT_STATUS_1 |
| 0x1E | DSD_OUT |
| 0x1E | GYR_CAS_GPIO0 |
| 0x1E | SC_OUT_0 |
| 0x1E | SYNC_COMMAND |
| 0x21 | INTERNAL_STATUS |
| 0x22 | TEMPERATURE_0 |
| 0x23 | TEMPERATURE_1 |
| 0x24 | FIFO_LENGTH_0 |
| 0x26 | FIFO_DATA |
| 0x2F | FEAT_PAGE |
| 0x30 | FEATURES_REG |
| 0x40 | ACC_CONF |
| 0x42 | GYR_CONF |
| 0x44 | AUX_CONF |
| 0x45 | FIFO_DOWNS |
| 0x46 | FIFO_WTM_0 |
| 0x47 | FIFO_WTM_1 |
| 0x48 | FIFO_CONFIG_0 |
| 0x49 | FIFO_CONFIG_1 |
| 0x4A | SATURATION |
| 0x4B | AUX_DEV_ID |
| 0x4C | AUX_IF_CONF |
| 0x4D | AUX_RD |
| 0x4E | AUX_WR |
| 0x4F | AUX_WR_DATA |
| 0x52 | ERR_REG_MSK |
| 0x53 | INT1_IO_CTRL |
| 0x54 | INT2_IO_CTRL |
| 0x55 | INT_LATCH |
| 0x56 | INT1_MAP_FEAT |
| 0x57 | INT2_MAP_FEAT |
| 0x58 | INT_MAP_DATA |
| 0x59 | INIT_CTRL |
| 0x5E | INIT_DATA |
| 0x5F | INTERNAL_ERR |
| 0x68 | I2C_PRIM |
| 0x69 | GYR_CRT_CONF |
| 0x69 | I2C_SEC |
| 0x6A | NVM_CONF |
| 0x6B | IF_CONF |
| 0x6C | DRV_STR |
| 0x6D | ACC_SELF_TEST |
| 0x6E | GYR_SELF_TEST_AXES |
| 0x6F | SELF_TEST_MEMS |
| 0x70 | NV_CONF |
| 0x71 | ACC_OFF_COMP_0 |
| 0x74 | GYR_OFF_COMP_3 |
| 0x77 | GYR_OFF_COMP_6 |
| 0x78 | GYR_USR_GAIN_0 |
| 0x7C | PWR_CONF |
| 0x7D | PWR_CTRL |
| 0x7E | CMD_REG |

# 关键复位默认值（PX4 驱动源码 src/drivers/imu/bosch/bmi270/BMI270.cpp 的 _register_cfg / 本板实测）
#   0x40 ACC_CONF 复位 0xA8 ； 0x42 GYR_CONF 复位 0xA9 ； 0x45 FIFO_DOWNS 复位 0x88
#   0x00 CHIP_ID 固定 0x24（只读）
