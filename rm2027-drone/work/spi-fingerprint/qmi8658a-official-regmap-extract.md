# QMI8658A 官方寄存器表（摘录，用于排除候选）

来源：QST 官方 Datasheet Rev A PDF
URL : https://www.qstcorp.com/upload/pdf/202301/13-52-25%20QMI8658A%20Datasheet%20Rev%20A.pdf
抓取：2026-09-30（pdftotext -layout 提取）

## 关键点
- WHO_AM_I @0x00 复位值 **0x05**；REVISION_ID @0x01 = 0x68；CTRL1 @0x02 = 0x20
- 3 字节 TIMESTAMP 在 **0x30/0x31/0x32**（不是 0x18）
- 加速度/陀螺数据在 0x35..0x40；通用寄存器 0x49..0x56；RESET(只写) @0x60
- 0x18~0x2C 未定义（保留）

## 原文摘录
```
     ▪     Activity Detection status registers
     ▪     General Purpose Registers
     Table 19. UI Register Overview

                                    Register Address           Default                               Comment
             Name           Type
                                   Dec Hex        Binary Binary
     General Purpose Registers
          WHO_AM_I            r      0     00    00000000 00000101 Device Identifier
         REVISION_ID          r      1     01    00000001 01101000 Device Revision ID
     Setup and Control Registers
             CTRL1           rw      2     02    00000010 00100000 SPI Interface and Sensor Enable
             CTRL2           rw      3     03    00000011 00000000 Accelerometer: Output Data Rate, Full Scale, Self-Test
             CTRL3           rw      4     04    00000100 00000000 Gyroscope: Output Data Rate, Full Scale, Self-Test
           Reserved          rw      5     05    00000101 00000000 Reserved
             CTRL5           rw      6     06    00000110 00000000 Low pass filter setting
           Reserved          rw      7     07    00000111 00000000 Reserved
             CTRL7           rw      8     08    00001000 00000000 Enable Sensors
             CTRL8           rw      9     09    00001001 00000000 Motion Detection Control
             CTRL9           rw     10     0A    00001010 00000000 Host Commands
     Host Controlled Calibration Registers (See CTRL9, Usage is Optional)
            CAL1_L           rw     11     0B    00001011 00000000 Calibration Register
            CAL1_H           rw     12     0C    00001100 00000000 CAL1_L – lower 8 bits. CAL1_H – upper 8 bits.
            CAL2_L           rw     13     0D    00001101 00000000 Calibration Register
            CAL2_H           rw     14     0E    00001110 00000000 CAL2_L – lower 8 bits. CAL2_H – upper 8 bits.
            CAL3_L           rw     15     0F    00001111 00000000 Calibration Register
            CAL3_H           rw     16     10    00010000 00000000 CAL3_L – lower 8 bits. CAL3_H – upper 8 bits.
            CAL4_L           rw     17     11    00010001 00000000 Calibration Register
            CAL4_H           rw     18     12    00010010 00000000 CAL4_L – lower 8 bits. CAL4_H – upper 8 bits.
     FIFO Registers
         FIFO_WTM_TH         rw     19     13    00010011 00000000 FIFO watermark level, in ODRs
          FIFO_CTRL          rw     20     14    00010100 00000000 FIFO Setup

© 2022 QST Corporation                            Document#: 13-52-25 ∙ QMI8658A Datasheet ∙ Rev A                www. qstcorp.com
                                                                                                                                 25
      FIFO_SMPL_CNT       r   21   15   00010101 00000000 FIFO sample count LSBs
       FIFO_STATUS        r   22   16   00010110 00000000 FIFO Status
         FIFO_DATA        r   23   17   00010111 00000000 FIFO Data
     Status Registers
                                                                  Sensor Data Availability with the Locking mechanism,
         STATUSINT        r   45   2D   00101101 00000000
                                                                  CmdDone (CTRL9 protocol bit).
          STATUS0         r   46   2E   00101110 00000000 Output Data Over Run and Data Availability.
                                                                  Miscellaneous Status: Any Motion, No Motion,
          STATUS1         r   47   2F   00101111 00000000
                                                                  Significant Motion, Pedometer, Tap.
     Timestamp Register
        TIMESTAMP_
                          r   48   30   00110000 00000000 Sample Time Stamp
           LOW
                                                          TIMESTAMP_LOW – lower 8 bits.
      TIMESTAMP_MID       r   49   31   00110001 00000000
                                                          TIMESTAMP_MID – middle 8 bits.
      TIMESTAMP_HIG
                          r   50   32   00110010 00000000 TIMESTAMP_HIGH – upper 8 bits
            H
     Data Output Registers (16 bits 2’s Complement Except COD Sensor Data)
           TEMP_L         r   51   33   00110011 00000000 Temperature Output Data
           TEMP_H         r   52   34   00110100 00000000 TEMP_L – lower 8 bits. TEMP_H – upper 8 bits
             AX_L         r   53   35   00110101 00000000 X-axis Acceleration
             AX_H         r   54   36   00110110 00000000 AX_L – lower 8 bits. AX_H – upper 8 bits
             AY_L         r   55   37   00110111 00000000 Y-axis Acceleration
             AY_H         r   56   38   00111000 00000000 AY_L – lower 8 bits. AY_H – upper 8 bits
             AZ_L         r   57   39   00111001 00000000 Z-axis Acceleration
             AZ_H         r   58   3A   00111010 00000000 AZ_L – lower 8 bits. AZ_H – upper 8 bits
             GX_L         r   59   3B   00111011 00000000 X-axis Angular Rate
             GX_H         r   60   3C   00111100 00000000 GX_L – lower 8 bits. GX_H – upper 8 bits
             GY_L         r   61   3D   00111101 00000000 Y-axis Angular Rate
             GY_H         r   62   3E   00111110 00000000 GY_L – lower 8 bits. GY_H – upper 8 bits
             GZ_L         r   63   3F   00111111 00000000 Z-axis Angular Rate
             GZ_H         r   64   40   01000000 00000000 GZ_L – lower 8 bits. GZ_H – upper 8 bits
     COD Indication and General Purpose Registers
       COD_STATUS         r   70   46   01000110 00000000 Calibration-On-Demand status register
            dQW_L         r   73   49   01001001 00000000 General purpose register
           dQW_H          r   74   4A   01001010 00000000 General purpose register
            dQX_L         r   75   4B   01001011 00000000 General purpose register
            dQX_H         r   76   4C   01001100 00000000 Reserved
            dQY_L         r   77   4D   01001101 00000000 General purpose register
            dQY_H         r   78   4E   01001110 00000000 Reserved
            dQZ_L         r   79   4F   01001111 00000000 Reserved
            dQZ_H         r   80   50   01010000 00000000 Reserved
            dVX_L         r   81   51   01010001 00000000 General purpose register
            dVX_H         r   82   52   01010010 00000000 General purpose register
            dVY_L         r   83   53   01010011 00000000 General purpose register
            dVY_H         r   84   54   01010100 00000000 General purpose register
            dVZ_L         r   85   55   01010101 00000000 General purpose register
            dVZ_H         r   86   56   01010110 00000000 General purpose register
© 2022 QST Corporation                   Document#: 13-52-25 ∙ QMI8658A Datasheet ∙ Rev A                  www. qstcorp.com
                                                                                                                          26
     Activity Detection Output Registers
        TAP_STATUS        r    89    59    01011001 00000000 Axis, direction, number of detected Tap
      STEP_CNT_LOW        r    90    5A    01011010 00000000 Low byte of step count of Pedometer
      STEP_CNT_MIDL       r    91    5B    01011011 00000000 Middle byte of step count of Pedometer
     STEP_CNT_HIGH        r    92    5C    01011100 00000000 High byte of step count of Pedometer
     Reset Register
            RESET        w     96    60    01100000 00000000 Soft Reset Register




© 2022 QST Corporation                      Document#: 13-52-25 ∙ QMI8658A Datasheet ∙ Rev A           www. qstcorp.com
                                                                                                                      27
     5 UI Sensor Configuration Settings and Output Data
     5.1     Typical Sensor Mode Configuration and Output Data
     In Typical sensor mode, QMI8658A outputs raw sensor values. The sensors are configured and read using the registers
     described below. The accelerometer and gyroscope can be independently configured. Table 20 summarizes these
     pertinent registers.
     Table 20. Typical Sensor Mode Configuration and Output Data

       Typical Sensor Configuration and Output Data
             Description           Registers       Unit                                  Comments
      Sensor Enable, SPI 3 or 4
```
