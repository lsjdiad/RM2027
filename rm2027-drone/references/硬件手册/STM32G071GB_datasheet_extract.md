Title: Datasheet - STM32G071x8/xB - Arm<Sup>® </Sup>Cortex<Sup>®</Sup>-M0+ 32-bit MCU, up to 128 KB Flash, 36 KB RAM, 4x USART, timers, ADC, DAC, comm. I/Fs, 1.7-3.6 V

URL Source: https://www.st.com/resource/en/datasheet/stm32g071gb.pdf

Number of Pages: 143

Markdown Content:
This is information on a product in full production. June 2025 DS12232 Rev 5 1/143 

# STM32G071x8/xB 

# Arm ® Cortex ®-M0+ 32-bit MCU, up to 128 KB Flash, 36 KB RAM, 4x USART, timers, ADC, DAC, comm. I/Fs, 1.7-3.6 V 

Datasheet  - production data 

# Features 

• Includes ST state-of-the-art patented technology 

• Core: Arm ® 32-bit Cortex ®-M0+ CPU, frequency up to 64 MHz 

• -40°C to 85°C/105°C/125°C operating temperature 

• Memories – Up to 128 Kbytes of flash memory with protection and securable area – 36 Kbytes of SRAM (32 Kbytes with HW parity check) 

• CRC calculation unit 

• Reset and power management – Voltage range: 1.7 V to 3.6 V – Power-on/Power-down reset (POR/PDR) – Programmable Brownout reset (BOR) – Programmable voltage detector (PVD) – Low-power modes: 

Sleep, Stop, Standby, Shutdown – VBAT supply for RTC and backup registers 

• Clock management – 4 to 48 MHz crystal oscillator – 32 kHz crystal oscillator with calibration – Internal 16 MHz RC with PLL option (±1 %) – Internal 32 kHz RC oscillator (±5 %) 

• Up to 60 fast I/Os – All mappable on external interrupt vectors – Multiple 5 V-tolerant I/Os 

• 7-channel DMA controller with flexible mapping 

• 12-bit, 0.4 μs ADC (up to 16 ext. channels) – Up to 16-bit with hardware oversampling – Conversion range: 0 to 3.6V 

• Two 12-bit DACs, low-power sample-and-hold 

• Two fast low-power analog comparators, with programmable input and output, rail-to-rail 

• 14 timers (two 128 MHz capable): 16-bit for advanced motor control, one 32-bit and five 16-bit general-purpose, two basic 16-bit, two low-power 16-bit, two watchdogs, SysTick timer 

• Calendar RTC with alarm and periodic wakeup from Stop/Standby/Shutdown 

• Communication interfaces – Two I 2C-bus interfaces supporting Fast-mode Plus (1 Mbit/s) with extra current sink, one supporting SMBus/PMBus and wakeup from Stop mode – Four USARTs with master/slave synchronous SPI; two supporting ISO7816 interface, LIN, IrDA capability, auto baud rate detection and wakeup feature – One low-power UART – Two SPIs (32 Mbit/s) with 4- to 16-bit programmable bitframe, one multiplexed with I 2S interface; four extra SPIs through USARTs – HDMI CEC interface, wakeup on header 

• USB Type-C™ Power Delivery controller 

• Development support: serial wire debug (SWD) 

• 96-bit unique ID 

• All packages ECOPACK 2 compliant 

Table 1. Device summary Reference Part number    

> STM32G071x8 STM32G071C8, STM32G071G8, STM32G071K8, STM32G071R8 STM32G071xB STM32G071CB, STM32G071EB, STM32G071GB, STM32G071KB, STM32G071RB
> LQFP64 UFQFPN48 UFQFPN32 UFQFPN28
> LQFP48 LQFP32 WLCSP25
> (2.3 × 2.5 mm) UFBGA64 (5 × 5 mm) (10 × 10 mm) (7 × 7 mm) (7 × 7 mm) (7 × 7 mm) (5 × 5 mm) (4 × 4 mm)
> www.st.com

Contents STM32G071x8/xB  

> 2/143 DS12232 Rev 5

# Contents 

## 1 Introduction . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 10 2 Description . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 11 3 Functional overview . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 14 

3.1 Arm ® Cortex ®-M0+ core with MPU . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 14 3.2 Memory protection unit . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 14 3.3 Embedded flash memory . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 14 3.3.1 Securable area . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 15 3.4 Embedded SRAM . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 16 3.5 Boot modes . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 16 3.6 Cyclic redundancy check calculation unit (CRC) . . . . . . . . . . . . . . . . . . . 16 3.7 Power supply management . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17 3.7.1 Power supply schemes . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17 3.7.2 Power supply supervisor . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 18 3.7.3 Voltage regulator . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 18 3.7.4 Low-power modes . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 19 3.7.5 Reset mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 20 3.7.6 VBAT operation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 20 3.8 Interconnect of peripherals . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 20 3.9 Clocks and startup . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 22 3.10 General-purpose inputs/outputs (GPIOs) . . . . . . . . . . . . . . . . . . . . . . . . . 22 3.11 Direct memory access controller (DMA) . . . . . . . . . . . . . . . . . . . . . . . . . . 23 3.12 DMA request multiplexer (DMAMUX) . . . . . . . . . . . . . . . . . . . . . . . . . . . . 23 3.13 Interrupts and events . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 23 3.13.1 Nested vectored interrupt controller (NVIC) . . . . . . . . . . . . . . . . . . . . . . 24 3.13.2 Extended interrupt/event controller (EXTI) . . . . . . . . . . . . . . . . . . . . . . 24 3.14 Analog-to-digital converter (ADC) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 25 3.14.1 Temperature sensor . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 25 3.14.2 Internal voltage reference (V REFINT ) . . . . . . . . . . . . . . . . . . . . . . . . . . . 26 3.14.3 VBAT battery voltage monitoring . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 26 3.15 Digital-to-analog converter (DAC) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 26 3.16 Voltage reference buffer (VREFBUF) . . . . . . . . . . . . . . . . . . . . . . . . . . . . 27 DS12232 Rev 5 3/143 

STM32G071x8/xB Contents 

> 5

3.17 Comparators (COMP) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 27 3.18 Timers and watchdogs . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 27 3.18.1 Advanced-control timer (TIM1) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 28 3.18.2 General-purpose timers (TIM2, 3, 14, 15, 16, 17) . . . . . . . . . . . . . . . . . 29 3.18.3 Basic timers (TIM6 and TIM7) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 29 3.18.4 Low-power timers (LPTIM1 and LPTIM2) . . . . . . . . . . . . . . . . . . . . . . . 29 3.18.5 Independent watchdog (IWDG) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 30 3.18.6 System window watchdog (WWDG) . . . . . . . . . . . . . . . . . . . . . . . . . . . 30 3.18.7 SysTick timer . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 30 3.19 Real-time clock (RTC), tamper (TAMP) and backup registers . . . . . . . . . 30 3.20 Inter-integrated circuit interface (I 2C) . . . . . . . . . . . . . . . . . . . . . . . . . . . . 31 3.21 Universal synchronous/asynchronous receiver transmitter (USART) . . . 32 3.22 Low-power universal asynchronous receiver transmitter (LPUART) . . . . 33 3.23 Serial peripheral interface (SPI) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 34 3.24 USB Type-C Power Delivery controller . . . . . . . . . . . . . . . . . . . . . . . . . . 34 3.25 Development support . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 35 3.25.1 Serial wire debug port (SW-DP) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 35 

## 4 Pinouts, pin description and alternate functions . . . . . . . . . . . . . . . . . 36 5 Electrical characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 

5.1 Parameter conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.1 Minimum and maximum values . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.2 Typical values . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.3 Typical curves . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.4 Loading capacitor . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.5 Pin input voltage . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 5.1.6 Power supply scheme . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 54 5.1.7 Current consumption measurement . . . . . . . . . . . . . . . . . . . . . . . . . . . 55 5.2 Absolute maximum ratings . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 55 5.3 Operating conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56 5.3.1 General operating conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56 5.3.2 Operating conditions at power-up / power-down . . . . . . . . . . . . . . . . . . 57 5.3.3 Embedded reset and power control block characteristics . . . . . . . . . . . 57 5.3.4 Embedded voltage reference . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 58 5.3.5 Supply current characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 59 Contents STM32G071x8/xB  

> 4/143 DS12232 Rev 5

5.3.6 Wakeup time from low-power modes and voltage scaling 

transition times . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 68 5.3.7 External clock source characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . 70 5.3.8 Internal clock source characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . 74 5.3.9 PLL characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 76 5.3.10 Flash memory characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 76 5.3.11 EMC characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 77 5.3.12 Electrical sensitivity characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . 79 5.3.13 I/O current injection characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . 79 5.3.14 I/O port characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 81 5.3.15 NRST input characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 85 5.3.16 Extended interrupt and event controller input (EXTI) characteristics . . . 86 5.3.17 Analog switch booster . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 87 5.3.18 Analog-to-digital converter characteristics . . . . . . . . . . . . . . . . . . . . . . . 87 5.3.19 Digital-to-analog converter characteristics . . . . . . . . . . . . . . . . . . . . . . . 94 5.3.20 Voltage reference buffer characteristics . . . . . . . . . . . . . . . . . . . . . . . . 98 5.3.21 Comparator characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 99 5.3.22 Temperature sensor characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . 100 5.3.23 VBAT monitoring characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 100 5.3.24 Timer characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 101 5.3.25 Characteristics of communication interfaces . . . . . . . . . . . . . . . . . . . . 102 

## 6 Package information . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 111 

6.1 Device marking . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 111 6.2 WLCSP25 package information . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .112 6.3 UFQFPN28 package information (A0B0) . . . . . . . . . . . . . . . . . . . . . . . . .115 6.4 LQFP32 package information (5V) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .117 6.5 UFQFPN32 package information (A0B8) . . . . . . . . . . . . . . . . . . . . . . . . 121 6.6 LQFP48 package information (5B) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 125 6.7 UFQFPN48 package information (A0B9) . . . . . . . . . . . . . . . . . . . . . . . . 128 6.8 LQFP64 package information (5W) . . . . . . . . . . . . . . . . . . . . . . . . . . . . 130 6.9 UFBGA64 package information (A019) . . . . . . . . . . . . . . . . . . . . . . . . . 133 6.10 Thermal characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 136 6.10.1 Reference document . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 137 6.10.2 Selecting the product temperature range . . . . . . . . . . . . . . . . . . . . . . 137 DS12232 Rev 5 5/143  

> STM32G071x8/xB Contents
> 5

## 7 Ordering information . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 139 8 Important security notice . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 140 9 Revision history . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 141 List of tables STM32G071x8/xB  

> 6/143 DS12232 Rev 5

# List of tables 

Table 1. Device summary . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 1 Table 2. STM32G071x8/xB device features and peripheral counts . . . . . . . . . . . . . . . . . . . . . . . . . 12 Table 3. Access status versus readout protection level and execution modes. . . . . . . . . . . . . . . . . 15 Table 4. Interconnect of peripherals . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 21 Table 5. Temperature sensor calibration values. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 25 Table 6. Internal voltage reference calibration values . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 26 Table 7. Timer feature comparison . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 27 Table 8. I2C implementation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 32 Table 9. USART implementation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 33 Table 10. SPI/I2S implementation . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 34 Table 11. Terms and symbols used in Pin assignment and description table . . . . . . . . . . . . . . . . . . 42 Table 12. Pin assignment and description . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 42 Table 13. Port A alternate function mapping . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 49 Table 14. Port B alternate function mapping . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 50 Table 15. Port C alternate function mapping . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 51 Table 16. Port D alternate function mapping . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 52 Table 17. Port F alternate function mapping. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 52 Table 18. Voltage characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 55 Table 19. Current characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 55 Table 20. Thermal characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56 Table 21. General operating conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 56 Table 22. Operating conditions at power-up / power-down . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 57 Table 23. Embedded reset and power control block characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . 57 Table 24. Embedded internal voltage reference . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 58 Table 25. Current consumption in Run and Low-power run modes 

at different die temperatures . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 60 Table 26. Typical current consumption in Run and Low-power run modes, 

depending on code executed . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 62 Table 27. Current consumption in Sleep and Low-power sleep modes . . . . . . . . . . . . . . . . . . . . . . . 63 Table 28. Current consumption in Stop 0 mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 63 Table 29. Current consumption in Stop 1 mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 64 Table 30. Current consumption in Standby mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 64 Table 31. Current consumption in Shutdown mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 65 Table 32. Current consumption in VBAT mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 65 Table 33. Current consumption of peripherals . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 67 Table 34. Low-power mode wakeup times . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 68 Table 35. Regulator mode transition times . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 69 Table 36. Wakeup time using LPUART . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 70 Table 37. High-speed external user clock characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 70 Table 38. Low-speed external user clock characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 71 Table 39. HSE oscillator characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 71 Table 40. LSE oscillator characteristics (f LSE = 32.768 kHz) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 73 Table 41. HSI16 oscillator characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 74 Table 42. LSI oscillator characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 75 Table 43. PLL characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 76 Table 44. Flash memory characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 76 Table 45. Flash memory endurance and data retention . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 77 Table 46. EMS characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 78 DS12232 Rev 5 7/143 

STM32G071x8/xB List of tables 

> 7

Table 47. EMI characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 78 Table 48. ESD absolute maximum ratings . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 79 Table 49. Electrical sensitivity. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 79 Table 50. I/O current injection susceptibility . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 80 Table 51. I/O static characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 81 Table 52. Output voltage characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 83 Table 53. Non-FT_c I/O output timing characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 84 Table 54. FT_c I/O output timing characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 85 Table 55. NRST pin characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 85 Table 56. EXTI input characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 86 Table 57. Analog switch booster characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 87 Table 58. ADC characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 87 Table 59. Maximum ADC R AIN . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 89 Table 60. ADC accuracy . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 90 Table 61. DAC characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 94 Table 62. DAC accuracy . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 96 Table 63. VREFBUF characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 98 Table 64. COMP characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 99 Table 65. TS characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 100 Table 66. VBAT monitoring characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 100 Table 67. VBAT charging characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 101 Table 68. TIMx characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 101 Table 69. IWDG min/max timeout period at 32 kHz LSI clock . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 102 Table 70. Minimum I2CCLK frequency . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 102 Table 71. I2C analog filter characteristics. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 103 Table 72. SPI characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 103 Table 73. I2S characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 106 Table 74. USART characteristics in SPI mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 108 Table 75. UCPD operating conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 110 Table 76. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip 

scale mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 112 Table 77. WLCSP25 recommended PCB design rules . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 113 Table 78. UFQFPN28 – Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 115 Table 79. LQFP32 - Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 118 Table 80. UFQFPN32 - Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 122 Table 81. Tolerance of form and position . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 122 Table 82. LQFP48 - Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 126 Table 83. UFQFPN48 – Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 129 Table 84. LQFP64 - Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 131 Table 85. UFBGA64 – Mechanical data . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 134 Table 86. UFBGA64 - Example of PCB design rules (0.5 mm pitch BGA) . . . . . . . . . . . . . . . . . . . . 135 Table 87. Package thermal characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 136 Table 88. Document revision history . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 141 List of figures STM32G071x8/xB  

> 8/143 DS12232 Rev 5

# List of figures 

Figure 1. Block diagram . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 13 Figure 2. Power supply overview . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 18 Figure 3. STM32G071Ex WLCSP25 ballout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 36 Figure 4. STM32G071GxU UFQFPN28 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 37 Figure 5. STM32G071KxT LQFP32 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 38 Figure 6. STM32G071KxU UFQFPN32 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 39 Figure 7. STM32G071CxT LQFP48 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 40 Figure 8. STM32G071CxU UFQFPN48 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 40 Figure 9. STM32G071RxT LQFP64 pinout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 41 Figure 10. STM32G071RxI UFBGA64 ballout . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 41 Figure 11. Pin loading conditions . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 Figure 12. Pin input voltage . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53 Figure 13. Power supply scheme. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 54 Figure 14. Current consumption measurement scheme . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 55 Figure 15. VREFINT vs. temperature . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 59 Figure 16. High-speed external clock source AC timing diagram . . . . . . . . . . . . . . . . . . . . . . . . . . . . 70 Figure 17. Low-speed external clock source AC timing diagram . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 71 Figure 18. Typical application with an 8 MHz crystal . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 73 Figure 19. Typical application with a 32.768 kHz crystal . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 74 Figure 20. HSI16 frequency vs. temperature . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 75 Figure 21. I/O input characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 82 Figure 22. I/O AC characteristics definition . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 85 Figure 23. Recommended NRST pin protection . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 86 Figure 24. ADC accuracy characteristics . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 93 Figure 25. ADC typical connection diagram. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 93 Figure 26. 12-bit buffered / non-buffered DAC. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 96 Figure 27. SPI timing diagram - slave mode and CPHA = 0 . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 105 Figure 28. SPI timing diagram - slave mode and CPHA = 1 . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 105 Figure 29. SPI timing diagram - master mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 106 Figure 30. I2S slave timing diagram (Philips protocol) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 107 Figure 31. I2S master timing diagram (Philips protocol). . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 108 Figure 32. USART timing diagram in SPI master mode. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 109 Figure 33. USART timing diagram in SPI slave mode . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 110 Figure 34. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip 

scale package outline . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 112 Figure 35. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip 

scale recommended footprint . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 113 Figure 36. WLCSP25 package marking example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 114 Figure 37. UFQFPN28 - Outline . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 115 Figure 38. UFQFPN28 – Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 116 Figure 39. LQFP32 - Outline . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 117 Figure 40. LQFP32 – Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 120 Figure 41. UFQFPN32 - Outline . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 121 Figure 42. UFQFPN32 - Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 124 Figure 43. LQFP48 - Outline (15) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 125 Figure 44. LQFP48 - Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 127 Figure 45. UFQFPN48 – Outline . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 128 Figure 46. UFQFPN48 – Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 129 DS12232 Rev 5 9/143 

STM32G071x8/xB List of figures 

> 9

Figure 47. LQFP64 - Outline (15) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 130 Figure 48. LQFP64 - Footprint example . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 132 Figure 49. UFBGA64 – Outline (13) . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 133 Figure 50. UFBGA64 – Footprint example. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 135 Introduction STM32G071x8/xB 

10/143 DS12232 Rev 5 

# 1 Introduction 

This document provides information on STM32G071x8/xB microcontrollers, such as description, functional overview, pin assignment and definition, electrical characteristics, packaging, and ordering codes. Information on memory mapping and control registers is object of reference manual RM0444. For information on the device errata with respect to the datasheet and reference manual, refer to the STM32G071x8/xB errata sheet ES0418. Information on Arm ®(a) Cortex ®-M0+ core is available from the www.arm.com website.   

> a. Arm is a registered trademark of Arm Limited (or its subsidiaries) in the US and/or elsewhere. DS12232 Rev 5 11/143

STM32G071x8/xB Description 

> 35

# 2 Description 

The STM32G071x8/xB mainstream microcontrollers are based on high-performance Arm ® Cortex ®-M0+ 32-bit RISC core operating at up to 64 MHz frequency. Offering a high level of integration, they are suitable for a wide range of applications in consumer, industrial and appliance domains and ready for the Internet of Things (IoT) solutions. The devices incorporate a memory protection unit (MPU), high-speed embedded memories (36 Kbytes of SRAM and up to 128 Kbytes of flash program memory with read protection, write protection, proprietary code protection, and securable area), DMA, an extensive range of system functions, enhanced I/Os, and peripherals. The devices offer standard communication interfaces (two I 2Cs, two SPIs / one I 2S, one HDMI CEC, and four USARTs), one 12-bit ADC (2.5 MSps) with up to 19 channels, one 12-bit DAC with two channels, two fast comparators, an internal voltage reference buffer, a low-power RTC, an advanced control PWM timer running at up to double the CPU frequency, five general-purpose 16-bit timers with one running at up to double the CPU frequency, a 32-bit general-purpose timer, two basic timers, two low-power 16-bit timers, two watchdog timers, and a SysTick timer. The devices provide a fully integrated USB Type-C Power Delivery controller. The devices operate within ambient temperatures from -40 to 125°C and with supply voltages from 1.7 V to 3.6 V. Optimized dynamic consumption combined with a comprehensive set of power-saving modes, low-power timers and low-power UART, allows the design of low-power applications. VBAT direct battery input allows keeping RTC and backup registers powered. The devices come in packages with 28 to 64 pins. Some packages with low pin count are available in two pinouts, standard and alternative. The devices with the alternative pinout, marked with N suffix, offer an additional UCPD port. They are the best choice for UCPD applications. Description STM32G071x8/xB 

12/143 DS12232 Rev 5 

Table 2. STM32G071x8/xB device features and peripheral counts Peripheral STM32G071_ _EB _G8 _GB _G8 xxN _GB xxN _K8 _KB _K8 xxN _KB xxN _C8 _CB _R8 _RB 

Flash memory (Kbyte) 128 64 128 64 128 64 128 64 128 64 128 64 128 SRAM (Kbyte) 32 (with parity) or 36 (without parity) Timers Advanced control 1 (16-bit) high frequency General-purpose 4 (16-bit) + 1 (16-bit) high frequency + 1 (32-bit) Basic 2 (16-bit) Low-power 2 (16-bit) SysTick 1Watchdog 2Comm. interfaces  SPI [I 2S] (1) 2 [1] + 4 extra through USARTs I2C 2USART 4LPUART 1UCPD 1(2) 2 1(2) 2CEC 1RTC Yes Tamper pins 2RNG / AES No / No GPIOs 23 26 30 44 60 Wakeup pins 4 3 4 3 4 512-bit ADC channels 10 ext. + 2 int. 9 ext. + 2 int. 11 ext. + 2 int. 10 ext. + 2 int. 14 ext. + 3 int. 16 ext. + 3 int. 12-bit DAC channels 2VREFBUF No Yes Analog comparators 2Max. CPU frequency 64 MHz Operating voltage 1.7 to 3.6 V Operating temperature (3) Ambient: -40 to 85 °C / -40 to 105 °C / -40 to 125 °C Junction: -40 to 105 °C / -40 to 125 °C / -40 to 130 °C Number of pins 25 28 32 48 64 1. The numbers in brackets denote the count of SPI interfaces configurable as I 2S interface. 2. One port with only one CC line available (supporting limited number of use cases). 3. Depends on order code. Refer to Section 7: Ordering information for details. DS12232 Rev 5 13/143 

STM32G071x8/xB Description 

35 

Figure 1. Block diagram 

MSv42182V2 UCPD USART3/4 USART1/2 LPTIMER 1/2 TIMER 16/17 Power domain of analog blocks : VBAT 4 channels BKIN, BKIN2, ETR System and peripheral clocks PAx PBx PCx PFx MOSI/SD MISO/MCK SCK/CK NSS/WS SWCLK SWDIO 16x IN OSC_IN OSC_OUT VBAT OSC32_IN OSC32_OUT RTC_OUT RTC_REFIN RTC_TS MOSI, MISO SCK, NSS HSI16 LSI PLLPCLK VDD IR_OUT 1 channel BKIN ETR, IN, OUT 1 channel 4 channels ETR 4 channels ETR CPU CORTEX-M0+ fmax = 64 MHz SWD NVIC EXTI SPI1/I2S SPI2 AHB-to-APB RCC Reset & clock control I/F XTAL OSC 4-48 MHz IWDG SRAM 36 KB I/F ADC RTC, TAMP Backup regs I/F RC 16 MHz RC 32 kHz PLL decoder XTAL32 kHz Bus matrix  I/F VDD 2 channels BKIN RX, TX CTS, RTS, CK RX, TX CTS, RTS, CK CEC TIM6 TIM7 COMP1 COMP2 IN+, IN-, OUT Port D Port C Port B Port A VDDA SUPPLY SUPERVISION POWER VCORE POR Reset Int VDD/VDDA VSS/VSSA NRST PVD POR/BOR Voltage regulator USART3 & 4 USART1 & 2 LPTIM1 & 2 TIM16 & 17 TIM15 TIM14 TIM3 TIM2 (32-bit) TIM1 GPIOs IOPORT HSE PLLQCLK PLLRCLK LSE LSE T sensor RX, TX, CTS, RTS LPUART TAMP_IN APB APB AHB CC, DBCC FRSTX UCPD1 & 2 HDMI-CEC VREFBUF DAC I/F DAC_OUT1 DAC_OUT2 CRC VREF+ SCL, SDA SCL, SDA SMBA, SMBUS I2C1 I2C2 DBGMCU WWDG PWRCTRL SYSCFG DMA DMAMUX Port F PDx VDDA VDDIO1 Low-voltage detector VDD Parity Flash memory up to 128 KB VDDIO1 IRTIM from peripherals Functional overview STM32G071x8/xB  

> 14/143 DS12232 Rev 5

# 3 Functional overview 3.1 Arm ® Cortex ®-M0+ core with MPU 

The Cortex-M0+ is an entry-level 32-bit Arm Cortex processor designed for a broad range of embedded applications. It offers significant benefits to developers, including: 

• a simple architecture, easy to learn and program 

• ultra-low power, energy-efficient operation 

• excellent code density 

• deterministic, high-performance interrupt handling 

• upward compatibility with Cortex-M processor family 

• platform security robustness, with integrated Memory Protection Unit (MPU). The Cortex-M0+ processor is built on a highly area- and power-optimized 32-bit core, with a 2-stage pipeline Von Neumann architecture. The processor delivers exceptional energy efficiency through a small but powerful instruction set and extensively optimized design, providing high-end processing hardware including a single-cycle multiplier. The Cortex-M0+ processor provides the exceptional performance expected of a modern 32-bit architecture, with a higher code density than other 8-bit and 16-bit microcontrollers. Owing to embedded Arm core, the STM32G071x8/xB devices are compatible with Arm tools and software. The Cortex-M0+ is tightly coupled with a nested vectored interrupt controller (NVIC) described in Section 3.13.1 .

# 3.2 Memory protection unit 

The memory protection unit (MPU) is used to manage the CPU accesses to memory to prevent one task to accidentally corrupt the memory or resources used by any other active task. The MPU is especially helpful for applications where some critical or certified code has to be protected against the misbehavior of other tasks. It is usually managed by an RTOS (real-time operating system). If a program accesses a memory location that is prohibited by the MPU, the RTOS can detect it and take action. In an RTOS environment, the kernel can dynamically update the MPU area setting, based on the process to be executed. The MPU is optional and can be bypassed for applications that do not need it. 

# 3.3 Embedded flash memory 

STM32G071x8/xB devices feature up to 128 Kbytes of embedded flash memory available for storing code and data. DS12232 Rev 5 15/143 

STM32G071x8/xB Functional overview 

> 35

Flexible protections can be configured thanks to option bytes: 

• Readout protection (RDP) to protect the whole memory. Three levels are available: – Level 0: no readout protection – Level 1: memory readout protection: the flash memory cannot be read from or written to if either debug features are connected, boot in RAM or bootloader is selected – Level 2: chip readout protection: debug features (Cortex-M0+ serial wire), boot in RAM and bootloader selection are disabled. This selection is irreversible. 

• Write protection (WRP): the protected area is protected against erasing and programming. Two areas per bank can be selected, with 2-Kbyte granularity. 

• Proprietary code readout protection (PCROP): a part of the flash memory can be protected against read and write from third parties. The protected area is execute-only: it can only be reached by the STM32 CPU as instruction code, while all other accesses (DMA, debug and CPU data read, write and erase) are strictly prohibited. An additional option bit (PCROP_RDP) determines whether the PCROP area is erased or not when the RDP protection is changed from Level 1 to Level 0. The whole non-volatile memory embeds the error correction code (ECC) feature supporting: 

• single error detection and correction 

• double error detection 

• readout of the ECC fail address from the ECC register 

## 3.3.1 Securable area 

A part of the flash memory can be hidden from the application once the code it contains is executed. As soon as the write-once SEC_PROT bit is set, the securable memory cannot be accessed until the system resets. The securable area generally contains the secure boot code to execute only once at boot. This helps to isolate secret code from untrusted application code. 

Table 3. Access status versus readout protection level and execution modes Area Protection level User execution Debug, boot from RAM or boot from system memory (loader) Read Write Erase Read Write Erase                                                              

> User memory 1Yes Yes Yes No No No 2Yes Yes Yes N/A N/A N/A System memory 1Yes No No Yes No No 2Yes No No N/A N/A N/A Option bytes 1Yes Yes Yes Yes Yes Yes 2Yes No No N/A N/A N/A Backup registers 1Yes Yes N/A (1) 1. Erased upon RDP change from Level 1 to Level 0. No No N/A (1) 2Yes Yes N/A N/A N/A N/A OTP 1Yes Yes N/A Yes No N/A 2Yes Yes N/A N/A N/A N/A

Functional overview STM32G071x8/xB  

> 16/143 DS12232 Rev 5

# 3.4 Embedded SRAM 

STM32G071x8/xB devices have 32 Kbytes of embedded SRAM with parity. Hardware parity check allows memory data errors to be detected, which contributes to increasing functional safety of applications. When the parity protection is not required because the application is not safety-critical, the parity memory bits can be used as additional SRAM, to increase its total size to 36 Kbytes. The memory can be read/write-accessed at CPU clock speed, with 0 wait states. 

# 3.5 Boot modes 

At startup, the boot pin and boot selector option bit are used to select one of the three boot options: 

• boot from User flash memory 

• boot from System memory 

• boot from embedded SRAM The boot pin is shared with a standard GPIO and can be enabled through the boot selector option bit. If the BOOT0 pin selects the boot from the main flash memory of which the first location is empty, the flash memory empty checker forces the boot from the system memory. The system memory contains an embedded boot loader. It manages the flash memory reprogramming through one of the following interfaces: 

• USART on pins PA9/PA10, PC10/PC11, or PA2/PA3 

• I2C-bus on pins PB6/PB7 or PB10/PB11 

• SPI on pins PA4/PA5/PA6/PA7 or PB12/PB13/PB14/PB15 When boot loader is executed, it configures some of the GPIOs out of their by-default high-Z state. Refer to AN2606 for more details on the boot loader and on the GPIO configuration when booting from the system memory. 

# 3.6 Cyclic redundancy check calculation unit (CRC) 

The CRC (cyclic redundancy check) calculation unit is used to get a CRC code using a configurable generator polynomial value and size. Among other applications, CRC-based techniques are used to verify data transmission or storage integrity. In the scope of the EN/IEC 60335-1 standard, they offer a means of verifying the flash memory integrity. The CRC calculation unit helps compute a signature of the software during runtime, to be compared with a reference signature generated at link time and stored at a given memory location. DS12232 Rev 5 17/143 

STM32G071x8/xB Functional overview 

> 35

# 3.7 Power supply management 3.7.1 Power supply schemes 

The STM32G071x8/xB devices require a 1.7 V to 3.6 V operating supply voltage (V DD ). Several different power supplies are provided to specific peripherals: 

• VDD = 1.7 (1.60) to 3.6 V VDD is the external power supply for the internal regulator and the system analog such as reset, power management and internal clocks. It is provided externally through VDD/VDDA pin. The minimum voltage of 1.7 V corresponds to power-on reset release threshold VPOR (max). Once this threshold is crossed and power-on reset is released, the functionality is guaranteed down to power-down reset threshold V PDR (min). 

• VDDA = 1.62 V (ADC and COMP) / 1.8 V (DAC) / 2.4 V (VREFBUF) to 3.6 V VDDA is the analog power supply for the A/D converter, D/A converter, voltage reference buffer and comparators. V DDA voltage level is identical to V DD voltage as it is provided externally through VDD/VDDA pin. 

• VDDIO1 = V DD VDDIO1 is the power supply for the I/Os. V DDIO1 voltage level is identical to V DD voltage as it is provided externally through VDD/VDDA pin. 

• VBAT = 1.55 V to 3.6 V. V BAT is the power supply (through a power switch) for RTC, TAMP, low-speed external 32.768 kHz oscillator and backup registers when V DD is not present. V BAT is provided externally through VBAT pin. When this pin is not available on the package, VBAT bonding pad is internally bonded to the VDD/VDDA pin. 

• VREF+ is the analog peripheral input reference voltage, or the output of the internal voltage reference buffer (when enabled). When V DDA < 2 V, V REF+ must be equal to VDDA . When V DDA ≥ 2 V, V REF+ must be between 2 V and V DDA . It can be grounded when the analog peripherals using V REF+ are not active. The internal voltage reference buffer supports two output voltages, which is configured with VRS bit of the VREFBUF_CSR register: – VREF+ around 2.048 V (requiring V DDA equal to or higher than 2.4 V) – VREF+ around 2.5 V (requiring V DDA equal to or higher than 2.8 V) VREF+ is delivered through VREF+ pin. On packages without VREF+ pin, V REF+ is internally connected with V DD , and the internal voltage reference buffer must be kept disabled (refer to datasheets for package pinout description). 

• VCORE is an internal supply for digital peripherals, SRAM and flash memory. It is produced by an embedded linear voltage regulator. On top of V CORE , the flash memory is also powered from V DD .Functional overview STM32G071x8/xB 

18/143 DS12232 Rev 5 

Figure 2. Power supply overview 3.7.2 Power supply supervisor 

The device has an integrated power-on/power-down (POR/PDR) reset active in all power modes except Shutdown and ensuring proper operation upon power-on and power-down. It maintains the device in reset when the supply voltage is below V POR/PDR threshold, without the need for an external reset circuit. Brownout reset (BOR) function allows extra flexibility. It can be enabled and configured through option bytes, by selecting one of four thresholds for rising V DD and other four for falling V DD .The device also features an embedded programmable voltage detector (PVD) that monitors the V DD power supply and compares it to V PVD threshold. It allows generating an interrupt when V DD level crosses the V PVD threshold, selectively while falling, while rising, or while falling and rising. The interrupt service routine can then generate a warning message and/or put the MCU into a safe state. The PVD is enabled by software. 

## 3.7.3 Voltage regulator 

Two embedded linear voltage regulators, main regulator (MR) and low-power regulator (LPR), supply most of digital circuitry in the device. The MR is used in Run and Sleep modes. The LPR is used in Low-power run, Low-power sleep and Stop modes. In Standby and Shutdown modes, both regulators are powered down and their outputs set in high-impedance state, such as to bring their current consumption close to zero. However, SRAM data retention is possible in Standby mode, in which case the LPR remains active and it only supplies the SRAM.  

> MSv39736V3 VDDA domain RTC domain D/A converter A/D converter Standby circuitry (Wakeup, IWDG) Voltage regulator Core SRAM Digital peripherals Low-voltage detector LSE crystal 32.768 kHz osc BKP registers RCC BDCR register RTC and TAMP Comparators Voltage reference buffer I/O ring VCORE domain Temp. sensor Reset block PLL, HSI Flash memory VDDIO1 VREF+ VDD domain VCORE VSS/VSSA VDD/VDDA VBAT VDDA VREF+ VSSA VSS VDD VDDIO1 domain DS12232 Rev 5 19/143

STM32G071x8/xB Functional overview 

> 35

## 3.7.4 Low-power modes 

By default, the microcontroller is in Run mode after system or power reset. It is up to the user to select one of the low-power modes described below. 

Sleep mode 

In Sleep mode, only the CPU is stopped. All peripherals continue to operate and can wake up the CPU when an interrupt/event occurs. 

Low-power run mode 

This mode is achieved with V CORE supplied by the low-power regulator to minimize the regulator's operating current. The code can be executed from SRAM or from flash memory, and the CPU frequency is limited to 2 MHz. The peripherals with independent clock can be clocked by HSI16. 

Low-power sleep mode 

This mode is entered from the low-power run mode. Only the CPU clock is stopped. When wakeup is triggered by an event or an interrupt, the system reverts to the Low-power run mode. 

Stop 0 and Stop 1 modes 

In Stop 0 and Stop 1 modes, the device achieves the lowest power consumption while retaining the SRAM and register contents. All clocks in the V CORE domain are stopped. The PLL, as well as the HSI16 RC oscillator and the HSE crystal oscillator are disabled. The LSE or LSI keep running. The RTC can remain active (Stop mode with RTC, Stop mode without RTC). Some peripherals with wakeup capability can enable the HSI16 RC during Stop mode, so as to get clock for processing the wakeup event. The main regulator remains active in Stop 0 mode while it is turned off in Stop 1 mode. 

Standby mode 

The Standby mode is used to achieve the lowest power consumption, with POR/PDR always active in this mode. The main regulator is switched off to power down V CORE domain. The low-power regulator is either switched off or kept active. In the latter case, it only supplies SRAM to ensure data retention. The PLL, as well as the HSI16 RC oscillator and the HSE crystal oscillator are also powered down. The RTC can remain active (Standby mode with RTC, Standby mode without RTC). For each I/O, the software can determine whether a pull-up, a pull-down or no resistor shall be applied to that I/O during Standby mode. Upon entering Standby mode, register contents are lost except for registers in the RTC domain and standby circuitry. The SRAM contents can be retained through register setting. The device exits Standby mode upon external reset event (NRST pin), IWDG reset event, wakeup event (WKUP pin, configurable rising or falling edge), RTC event (alarm, periodic wakeup, timestamp), TAMP event, or when a failure is detected on LSE (CSS on LSE). Functional overview STM32G071x8/xB  

> 20/143 DS12232 Rev 5

Shutdown mode 

The Shutdown mode allows to achieve the lowest power consumption. The internal regulator is switched off to power down the V CORE domain. The PLL, as well as the HSI16 and LSI RC-oscillators and HSE crystal oscillator are also powered down. The RTC can remain active (Shutdown mode with RTC, Shutdown mode without RTC). The BOR is not available in Shutdown mode. No power voltage monitoring is possible in this mode. Therefore, switching to RTC domain is not supported. SRAM and register contents are lost except for registers in the RTC domain. The device exits Shutdown mode upon external reset event (NRST pin), wakeup event (WKUP pin, configurable rising or falling edge), RTC event (alarm, periodic wakeup, timestamp), or TAMP event. 

## 3.7.5 Reset mode 

During and upon exiting reset, the schmitt triggers of I/Os are disabled so as to reduce power consumption. In addition, when the reset source is internal, the built-in pull-up resistor on NRST pin is deactivated. 

## 3.7.6 VBAT operation 

The V BAT power domain, consuming very little energy, includes RTC, and LSE oscillator and backup registers. In VBAT mode, the RTC domain is supplied from VBAT pin. The power source can be, for example, an external battery or an external supercapacitor. Two anti-tamper detection pins are available. The RTC domain can also be supplied from V DD .By means of a built-in switch, an internal voltage supervisor allows automatic switching of RTC domain powering between V DD and voltage from VBAT pin to ensure that the supply voltage of the RTC domain (V BAT ) remains within valid operating conditions. If both voltages are valid, the RTC domain is supplied from V DD .An internal circuit for charging the battery on VBAT pin can be activated if the V DD voltage is within a valid range. 

Note: External interrupts and RTC alarm/events cannot cause the microcontroller to exit the VBAT mode, as in that mode the V DD  is not within a valid range. 

# 3.8 Interconnect of peripherals 

Several peripherals have direct connections between them. This allows autonomous communication between peripherals, saving CPU resources thus power supply consumption. In addition, these hardware connections allow fast and predictable latency. Depending on peripherals, these interconnections can operate in Run, Sleep and Stop modes. DS12232 Rev 5 21/143 

STM32G071x8/xB Functional overview 

> 35

Table 4. Interconnect of peripherals Interconnect source Interconnect destination Interconnect action Run Low-power run Sleep Low-power sleep Stop 

TIMx TIMx Timer synchronization or chaining Y Y -ADCx DACx Conversion triggers Y Y -DMA Memory-to-memory transfer trigger Y Y -COMPx Comparator output blanking Y Y -COMPx TIM1,2,3 Timer input channel, trigger, break from analog signals comparison Y Y -LPTIMERx Low-power timer triggered by analog signals comparison Y Y YADCx TIM1 Timer triggered by analog watchdog Y Y -RTC TIM16 Timer input channel from RTC events Y Y -LPTIMERx Low-power timer triggered by RTC alarms or tampers Y Y YAll clock sources (internal and external) TIM14,16,17 Clock source used as input channel for RC measurement and trimming Y Y -CSS RAM (parity error) Flash memory (ECC error) COMPx PVD TIM1,15,16,17 Timer break Y Y -CPU (hard fault) TIM1,15,16,17 Timer break Y - -GPIO TIMx External trigger Y Y -LPTIMERx External trigger Y Y YADC DACx Conversion external trigger Y Y -Functional overview STM32G071x8/xB  

> 22/143 DS12232 Rev 5

# 3.9 Clocks and startup 

The clock controller distributes the clocks coming from different oscillators to the core and the peripherals. It also manages clock gating for low-power modes and ensures clock robustness. It features: 

• Clock prescaler: to get the best trade-off between speed and current consumption, the clock frequency to the CPU and peripherals can be adjusted by a programmable prescaler 

• Safe clock switching: clock sources can be changed safely on the fly in run mode through a configuration register. 

• Clock management: to reduce power consumption, the clock controller can stop the clock to the core, individual peripherals or memory. 

• System clock source: three different sources can deliver SYSCLK system clock: – 4-48 MHz high-speed oscillator with external crystal or ceramic resonator (HSE). It can supply clock to system PLL. The HSE can also be configured in bypass mode for an external clock. – 16 MHz high-speed internal RC oscillator (HSI16), trimmable by software. It can supply clock to system PLL. – System PLL with maximum output frequency of 64 MHz. It can be fed with HSE or HSI16 clocks. 

• Auxiliary clock source: two ultra-low-power clock sources for the real-time clock (RTC): – 32.768 kHz low-speed oscillator with external crystal (LSE), supporting four drive capability modes. The LSE can also be configured in bypass mode for using an external clock. – 32 kHz low-speed internal RC oscillator (LSI) with ±5% accuracy, also used to clock an independent watchdog. 

• Peripheral clock sources: several peripherals ( I2S, USARTs, I2Cs, LPTIMs, ADC) have their own clock independent of the system clock. 

• Clock security system (CSS): in the event of HSE clock failure, the system clock is automatically switched to HSI16 and, if enabled, a software interrupt is generated. LSE clock failure can also be detected and generate an interrupt. The CCS feature can be enabled by software. 

• Clock output: 

– MCO (microcontroller clock output) provides one of the internal clocks for external use by the application – LSCO (low speed clock output) provides LSI or LSE in all low-power modes (except in VBAT operation). Several prescalers allow the application to configure AHB and APB domain clock frequencies, 64 MHz at maximum. 

# 3.10 General-purpose inputs/outputs (GPIOs) 

Each of the GPIO pins can be configured by software as output (push-pull or open-drain), as input (with or without pull-up or pull-down) or as peripheral alternate function (AF). Most of the GPIO pins are shared with special digital or analog functions. DS12232 Rev 5 23/143 

STM32G071x8/xB Functional overview 

> 35

Through a specific sequence, this special function configuration of I/Os can be locked, such as to avoid spurious writing to I/O control registers. 

# 3.11 Direct memory access controller (DMA) 

The direct memory access (DMA) controller is a bus master and system peripheral with single-AHB architecture. With 7 channels, it performs data transfers between memory-mapped peripherals and/or memories, to offload the CPU. Each channel is dedicated to managing memory access requests from one or more peripherals. The unit includes an arbiter for handling the priority between DMA requests. Main features of the DMA controller: 

• Single-AHB master 

• Peripheral-to-memory, memory-to-peripheral, memory-to-memory and peripheral-to-peripheral data transfers 

• Access, as source and destination, to on-chip memory-mapped devices such as flash memory, SRAM, and AHB and APB peripherals 

• All DMA channels independently configurable: – Each channel is associated either with a DMA request signal coming from a peripheral, or with a software trigger in memory-to-memory transfers. This configuration is done by software. – Priority between the requests is programmable by software (four levels per channel: very high, high, medium, low) and by hardware in case of equality (such as request to channel 1 has priority over request to channel 2). – Transfer size of source and destination are independent (byte, half-word, word), emulating packing and unpacking. Source and destination addresses must be aligned on the data size. – Support of transfers from/to peripherals to/from memory with circular buffer management – Programmable number of data to be transferred: 0 to 2 16 - 1 

• Generation of an interrupt request per channel. Each interrupt request originates from any of the three DMA events: transfer complete, half transfer, or transfer error. 

# 3.12 DMA request multiplexer (DMAMUX) 

The DMAMUX request multiplexer enables routing a DMA request line between the peripherals and the DMA controller. Each channel selects a unique DMA request line, unconditionally or synchronously with events from its DMAMUX synchronization inputs. DMAMUX may also be used as a DMA request generator from programmable events on its input trigger signals. 

# 3.13 Interrupts and events 

The device flexibly manages events causing interrupts of linear program execution, called exceptions. The Cortex-M0+ processor core, a nested vectored interrupt controller (NVIC) Functional overview STM32G071x8/xB  

> 24/143 DS12232 Rev 5

and an extended interrupt/event controller (EXTI) are the assets contributing to handling the exceptions. Exceptions include core-internal events such as, for example, a division by zero and, core-external events such as logical level changes on physical lines. Exceptions result in interrupting the program flow, executing an interrupt service routine (ISR) then resuming the original program flow. The processor context (contents of program pointer and status registers) is stacked upon program interrupt and unstacked upon program resume, by hardware. This avoids context stacking and unstacking in the interrupt service routines (ISRs) by software, thus saving time, code and power. The ability to abandon and restart load-multiple and store-multiple operations significantly increases the device’s responsiveness in processing exceptions. 

## 3.13.1 Nested vectored interrupt controller (NVIC) 

The configurable nested vectored interrupt controller is tightly coupled with the core. It handles physical line events associated with a non-maskable interrupt (NMI) and maskable interrupts, and Cortex-M0+ exceptions. It provides flexible priority management. The tight coupling of the processor core with NVIC significantly reduces the latency between interrupt events and start of corresponding interrupt service routines (ISRs). The ISR vectors are listed in a vector table, stored in the NVIC at a base address. The vector address of an ISR to execute is hardware-built from the vector table base address and the ISR order number used as offset. If a higher-priority interrupt event happens while a lower-priority interrupt event occurring just before is waiting for being served, the later-arriving higher-priority interrupt event is served first. Another optimization is called tail-chaining. Upon a return from a higher-priority ISR then start of a pending lower-priority ISR, the unnecessary processor context unstacking and stacking is skipped. This reduces latency and contributes to power efficiency. Features of the NVIC: 

• Low-latency interrupt processing 

• 4 priority levels 

• Handling of a non-maskable interrupt (NMI) 

• Handling of 32 maskable interrupt lines 

• Handling of 10 Cortex-M0+ exceptions 

• Later-arriving higher-priority interrupt processed first 

• Tail-chaining 

• Interrupt vector retrieval by hardware 

## 3.13.2 Extended interrupt/event controller (EXTI) 

The extended interrupt/event controller adds flexibility in handling physical line events and allows identifying wake-up events at processor wakeup from Stop mode. The EXTI controller has a number of channels, of which some with rising, falling or rising, and falling edge detector capability. Any GPIO and a few peripheral signals can be connected to these channels. The channels can be independently masked. The EXTI controller can capture pulses shorter than the internal clock period. DS12232 Rev 5 25/143 

STM32G071x8/xB Functional overview 

> 35

A register in the EXTI controller latches every event even in Stop mode, which allows the software to identify the origin of the processor's wake-up from Stop mode or, to identify the GPIO and the edge event having caused an interrupt. 

# 3.14 Analog-to-digital converter (ADC) 

A native 12-bit analog-to-digital converter is embedded into STM32G071x8/xB devices. The ADC has up to 16 external channels and 3 internal channels (temperature sensor, voltage reference, V BAT monitoring). It performs conversions in single-shot or scan mode. In scan mode, automatic conversion is performed on a selected group of analog inputs. The ADC frequency is independent from the CPU frequency, allowing maximum sampling rate of ~2.5 MSps even with a low CPU speed. An auto-shutdown function guarantees that the ADC is powered off except during the active conversion phase. The ADC can be served by the DMA controller. It can operate in the whole V DD supply range. The ADC features a hardware oversampler up to 256 samples, improving the resolution to 16 bits (refer to AN2668). An analog watchdog feature allows very precise monitoring of the converted voltage of one, some or all scanned channels. An interrupt is generated when the converted voltage is outside the programmed thresholds. The events generated by the general-purpose timers (TIMx) can be internally connected to the ADC start triggers, to allow the application to synchronize A/D conversions with timers. 

## 3.14.1 Temperature sensor 

The temperature sensor (TS) generates a voltage VTS that varies linearly with temperature. The temperature sensor is internally connected to an ADC input to convert the sensor output voltage into a digital value. The sensor provides good linearity but it has to be calibrated to obtain good overall accuracy of the temperature measurement. As the offset of the temperature sensor may vary from part to part due to process variation, the uncalibrated internal temperature sensor is suitable only for relative temperature measurements. To improve the accuracy of the temperature sensor, each part is individually factory-calibrated by ST. The resulting calibration data are stored in the part’s engineering bytes, accessible in read-only mode. 

Table 5. Temperature sensor calibration values Calibration value name Description Memory address 

> TS_CAL1 TS ADC raw data acquired at a temperature of 30 °C (± 5 °C), VDDA = V REF+ = 3.0 V (± 10 mV) 0x1FFF 75A8 - 0x1FFF 75A9 TS_CAL2 TS ADC raw data acquired at a temperature of 130 °C (± 5 °C), VDDA = V REF+ = 3.0 V (± 10 mV) 0x1FFF 75CA - 0x1FFF 75CB

Functional overview STM32G071x8/xB  

> 26/143 DS12232 Rev 5

## 3.14.2 Internal voltage reference (VREFINT) 

The internal voltage reference (V REFINT ) provides a stable (bandgap) voltage output for the ADC and comparators. V REFINT is internally connected to an ADC input. The V REFINT voltage is individually precisely measured for each part by ST during production test and stored in the part’s engineering bytes. It is accessible in read-only mode. 

## 3.14.3 VBAT battery voltage monitoring 

This embedded hardware feature allows the application to measure the V BAT battery voltage using an internal ADC input. As the V BAT voltage may be higher than V DDA and thus outside the ADC input range, the VBAT pin is internally connected to a bridge divider by three. As a consequence, the converted digital value is one third the V BAT voltage. 

# 3.15 Digital-to-analog converter (DAC) 

The 2-channel 12-bit buffered DAC converts a digital value into an analog voltage available on the channel output. The architecture of either channel is based on integrated resistor string and an inverting amplifier. The digital circuitry is common for both channels. Features of the DAC: 

• Two DAC output channels 

• 8-bit or 12-bit output mode 

• Buffer offset calibration (factory and user trimming) 

• Left or right data alignment in 12-bit mode 

• Synchronized update capability 

• Noise-wave generation 

• Triangular-wave generation 

• Independent or simultaneous conversion for DAC channels 

• DMA capability for either DAC channel 

• Triggering with timer events, synchronized with DMA 

• Triggering with external events 

• Sample-and-hold low-power mode, with internal or external capacitor 

Table 6. Internal voltage reference calibration values Calibration value name Description Memory address 

VREFINT Raw data acquired at a temperature of 30 °C (± 5 °C), VDDA = VREF+ = 3.0 V (± 10 mV) 0x1FFF 75AA - 0x1FFF 75AB DS12232 Rev 5 27/143 

STM32G071x8/xB Functional overview 

> 35

# 3.16 Voltage reference buffer (VREFBUF) 

# 3.17 Comparators (COMP) 

Two embedded rail-to-rail analog comparators have programmable reference voltage (internal or external), hysteresis, speed (low for low-power) and output polarity. The reference voltage can be one of the following: 

• external, from an I/O 

• internal, from DAC 

• internal reference voltage (V REFINT ) or its submultiple (1/4, 1/2, 3/4) The comparators can wake up the device from Stop mode, generate interrupts, breaks or triggers for the timers and can be also combined into a window comparator. 

# 3.18 Timers and watchdogs 

The device includes an advanced-control timer, six general-purpose timers, two basic timers, two low-power timers, two watchdog timers and a SysTick timer. Table 7 compares features of the advanced-control, general-purpose and basic timers. When enabled, an embedded buffer provides the internal reference voltage to analog blocks (for example ADC) and to VREF+ pin for external components. The internal voltage reference buffer supports two voltages: 

• 2.048 V 

• 2.5 V An external voltage reference can be provided through the VREF+ pin when the internal voltage reference buffer is disabled. On some packages, the VREF+ pad of the silicon die is double-bonded with supply pad to common VDD/VDDA pin and so the internal voltage reference buffer cannot be used. 

Table 7. Timer feature comparison Timer type Timer Counter resolutio nCounter type Maximum operating frequency Prescaler factor DMA request generation Capture/ compare channels Comple-mentary outputs         

> Advanced-control TIM1 16-bit Up, down, up/down 128 MHz Integer from 1 to 2 16 Yes 4+ 2 internal 3

Functional overview STM32G071x8/xB  

> 28/143 DS12232 Rev 5

## 3.18.1 Advanced-control timer (TIM1) 

The advanced-control timer can be seen as a three-phase PWM unit multiplexed on 6 channels. It has complementary PWM outputs with programmable inserted dead-times. It can also be seen as a complete general-purpose timer. The four independent channels can be used for: 

• input capture 

• output compare 

• PWM output (edge or center-aligned modes) with full modulation capability (0-100%) 

• one-pulse mode output On top of these, there are two internal channels that can be used. In debug mode, the advanced-control timer counter can be frozen and the PWM outputs disabled, so as to turn off any power switches driven by these outputs. Many features are shared with those of the general-purpose TIMx timers (described in 

Section 3.18.2 ) using the same architecture, so the advanced-control timers can work together with the TIMx timers via the Timer Link feature for synchronization or event chaining. General-purpose TIM2 32-bit Up, down, up/down 64 MHz Integer from 1 to 2 16 Yes 4 -TIM3 16-bit Up, down, up/down 64 MHz Integer from 1 to 2 16 Yes 4 -TIM14 16-bit Up 64 MHz Integer from 1 to 2 16 No 1 -TIM15 16-bit Up 128 MHz Integer from 1 to 2 16 Yes 2 1TIM16 TIM17 16-bit Up 64 MHz Integer from 1 to 2 16 Yes 1 1Basic TIM6 TIM7 16-bit Up 64 MHz Integer from 1 to 2 16 Yes - -Low-power LPTIM1 LPTIM2 16-bit Up 64 MHz 2n where n=0 to 7 No N/A -

Table 7. Timer feature comparison (continued) Timer type Timer Counter resolutio nCounter type Maximum operating frequency Prescaler factor DMA request generation Capture/ compare channels Comple-mentary outputs DS12232 Rev 5 29/143 

STM32G071x8/xB Functional overview 

> 35

## 3.18.2 General-purpose timers (TIM2, 3, 14, 15, 16, 17) 

There are six synchronizable general-purpose timers embedded in the device (refer to 

Table 7 for comparison). Each general-purpose timer can be used to generate PWM outputs or act as a simple timebase. 

• TIM2, TIM3 These are full-featured general-purpose timers: – TIM2 with 32-bit auto-reload up/downcounter and 16-bit prescaler – TIM3 with 16-bit auto-reload up/downcounter and 16-bit prescaler They have four independent channels for input capture/output compare, PWM or one-pulse mode output. They can operate together or in combination with other general-purpose timers via the Timer Link feature for synchronization or event chaining. They can generate independent DMA request and support quadrature encoders. Their counters can be frozen in debug mode. 

• TIM14 This timer is based on a 16-bit auto-reload upcounter and a 16-bit prescaler. It has one channel for input capture/output compare, PWM output or one-pulse mode output. Its counter can be frozen in debug mode. 

• TIM15, TIM16, TIM17 These are general-purpose timers featuring: – 16-bit auto-reload upcounter and 16-bit prescaler – 2 channels and 1 complementary channel for TIM15 – 1 channel and 1 complementary channel for TIM16 and TIM17 All channels can be used for input capture/output compare, PWM or one-pulse mode output. The timers can operate together via the Timer Link feature for synchronization or event chaining. They can generate independent DMA request. Their counters can be frozen in debug mode. 

## 3.18.3 Basic timers (TIM6 and TIM7) 

## 3.18.4 Low-power timers (LPTIM1 and LPTIM2) 

These timers have an independent clock. When fed with LSE, LSI or external clock, they keep running in Stop mode and they can wake up the system from it. These timers are mainly used for triggering DAC conversions. They can also be used as generic 16-bit timebases. Functional overview STM32G071x8/xB  

> 30/143 DS12232 Rev 5

Features of LPTIM1 and LPTIM2: 

• 16-bit up counter with 16-bit autoreload register 

• 16-bit compare register 

• Configurable output (pulse, PWM) 

• Continuous/one-shot mode 

• Selectable software/hardware input trigger 

• Selectable clock source: – Internal: LSE, LSI, HSI16 or APB clocks – External: over LPTIM input (working even with no internal clock source running, used by pulse counter application) 

• Programmable digital glitch filter 

• Encoder mode 

## 3.18.5 Independent watchdog (IWDG) 

The independent watchdog is based on an 8-bit prescaler and 12-bit downcounter with user-defined refresh window. It is clocked from an independent 32 kHz internal RC (LSI). Independent of the main clock, it can operate in Stop and Standby modes. It can be used either as a watchdog to reset the device when a problem occurs, or as a free-running timer for application timeout management. It is hardware- or software-configurable through the option bytes. Its counter can be frozen in debug mode. 

## 3.18.6 System window watchdog (WWDG) 

The window watchdog is based on a 7-bit downcounter that can be set as free-running. It can be used as a watchdog to reset the device when a problem occurs. It is clocked by the system clock. It has an early-warning interrupt capability. Its counter can be frozen in debug mode. 

## 3.18.7 SysTick timer 

This timer is dedicated to real-time operating systems, but it can also be used as a standard down counter. Features of SysTick timer: 

• 24-bit down counter 

• Autoreload capability 

• Maskable system interrupt generation when the counter reaches 0 

• Programmable clock source 

# 3.19 Real-time clock (RTC), tamper (TAMP) and backup registers 

The device embeds an RTC and five 32-bit backup registers, located in the RTC domain of the silicon die. The ways of powering the RTC domain are described in Section 3.7.6 .The RTC is an independent BCD timer/counter. DS12232 Rev 5 31/143 

STM32G071x8/xB Functional overview 

> 35

Features of the RTC: 

• Calendar with subsecond, seconds, minutes, hours (12 or 24 format), week day, date, month, year, in BCD (binary-coded decimal) format 

• Automatic correction for 28, 29 (leap year), 30, and 31 days of the month 

• Programmable alarm 

• On-the-fly correction from 1 to 32767 RTC clock pulses, usable for synchronization with a master clock 

• Reference clock detection - a more precise second-source clock (50 or 60 Hz) can be used to improve the calendar precision 

• Digital calibration circuit with 0.95 ppm resolution, to compensate for quartz crystal inaccuracy 

• Two anti-tamper detection pins with programmable filter 

• Timestamp feature to save a calendar snapshot, triggered by an event on the timestamp pin or a tamper event, or by switching to VBAT mode 

• 17-bit auto-reload wakeup timer (WUT) for periodic events, with programmable resolution and period 

• Multiple clock sources and references: – A 32.768 kHz external crystal (LSE) – An external resonator or oscillator (LSE) – The internal low-power RC oscillator (LSI, with typical frequency of 32 kHz) – The high-speed external clock (HSE) divided by 32 When clocked by LSE, the RTC operates in VBAT mode and in all low-power modes. When clocked by LSI, the RTC does not operate in VBAT mode, but it does in low-power modes except for the Shutdown mode. All RTC events (Alarm, WakeUp Timer, Timestamp or Tamper) can generate an interrupt and wake the device up from the low-power modes. The backup registers allow keeping 20 bytes of user application data in the event of V DD failure, if a valid backup supply voltage is provided on VBAT pin. They are not affected by the system reset, power reset, and upon the device’s wakeup from Standby or Shutdown modes. 

# 3.20 Inter-integrated circuit interface (I2C) 

The device embeds two I2C peripherals. Refer to Table 8 for the features. The I 2C-bus interface handles communication between the microcontroller and the serial I2C-bus. It controls all I 2C-bus-specific sequencing, protocol, arbitration and timing. Functional overview STM32G071x8/xB  

> 32/143 DS12232 Rev 5

Features of the I2C peripheral: 

• I2C-bus specification and user manual rev. 5 compatibility: – Slave and master modes, multimaster capability – Standard-mode (Sm), with a bitrate up to 100 kbit/s – Fast-mode (Fm), with a bitrate up to 400 kbit/s – Fast-mode Plus (Fm+), with a bitrate up to 1 Mbit/s and extra output drive I/Os – 7-bit and 10-bit addressing mode, multiple 7-bit slave addresses – Programmable setup and hold times – Clock stretching 

• SMBus specification rev 3.0 compatibility: – Hardware PEC (packet error checking) generation and verification with ACK control – Command and data acknowledge control – Address resolution protocol (ARP) support – Host and Device support – SMBus alert – Timeouts and idle condition detection 

• PMBus rev 1.3 standard compatibility 

• Independent clock: a choice of independent clock sources allowing the I2C communication speed to be independent of the PCLK reprogramming 

• Wakeup from Stop mode on address match 

• Programmable analog and digital noise filters 

• 1-byte buffer with DMA capability 

# 3.21 Universal synchronous/asynchronous receiver transmitter (USART) 

The device embeds universal synchronous/asynchronous receivers/transmitters that communicate at speeds of up to 8 Mbit/s. They provide hardware management of the CTS, RTS and RS485 DE signals, multiprocessor communication mode, SPI synchronous communication and single-wire 

Table 8. I 2C implementation I2C features (1)                 

> 1. X: supported
> I2C1 I2C2
> Standard mode (up to 100 kbit/s) XXFast mode (up to 400 kbit/s) XXFast Mode Plus (up to 1 Mbit/s) with extra output drive I/Os XXProgrammable analog and digital noise filters XXSMBus/PMBus hardware support X-Independent clock X-Wakeup from Stop mode on address match X-

DS12232 Rev 5 33/143 

STM32G071x8/xB Functional overview 

> 35

half-duplex communication mode. Some can also support SmartCard communication (ISO 7816), IrDA SIR ENDEC, LIN Master/Slave capability and auto baud rate feature, and have a clock domain independent of the CPU clock, which allows them to wake up the MCU from Stop mode. The wakeup events from Stop mode are programmable and can be: 

• start bit detection 

• any received data frame 

• a specific programmed data frame All USART interfaces can be served by the DMA controller. 

# 3.22 Low-power universal asynchronous receiver transmitter (LPUART) 

The device embeds one LPUART. The peripheral supports asynchronous serial communication with minimum power consumption. It supports half duplex single wire communication and modem operations (CTS/RTS). It allows multiprocessor communication. The LPUART has a clock domain independent of the CPU clock, and can wakeup the system from Stop mode. The Stop mode wakeup events are programmable and can be: 

• start bit detection 

• any received data frame 

• a specific programmed data frame Only a 32.768 kHz clock (LSE) is needed to allow LPUART communication up to 9600 baud. Therefore, even in Stop mode, the LPUART can wait for an incoming frame while 

Table 9. USART implementation USART modes/features (1)  

> 1. X: supported

USART1 USART2 USART3 USART4 

Hardware flow control for modem X XContinuous communication using DMA X XMultiprocessor communication X XSPI emulation master/slave (synchronous mode) X XSmartcard mode X -Single-wire half-duplex communication X XIrDA SIR ENDEC block X -LIN mode X -Dual clock domain and wakeup from Stop mode X -Receiver timeout interrupt X -Modbus communication X -Auto baud rate detection X -Driver Enable X XFunctional overview STM32G071x8/xB  

> 34/143 DS12232 Rev 5

having an extremely low energy consumption. Higher speed clock can be used to reach higher baudrates. The LPUART interface can be served by the DMA controller. 

# 3.23 Serial peripheral interface (SPI) 

The device contains two SPIs running at up to 32 Mbits/s in master and slave modes. It supports half-duplex, full-duplex and simplex communications. A 3-bit prescaler gives eight master mode frequencies. The frame size is configurable from 4 bits to 16 bits. The SPI peripherals support NSS pulse mode, TI mode and hardware CRC calculation. The SPI peripherals can be served by the DMA controller. The I 2S interface mode of the SPI peripheral (if supported, see the following table) supports four different audio standards can operate as master or slave, in half-duplex communication mode. It can be configured to transfer 16 and 24 or 32 bits with 16-bit or 32-bit data resolution and synchronized by a specific signal. Audio sampling frequency from 8 kHz up to 192 kHz can be set by an 8-bit programmable linear prescaler. When operating in master mode, it can output a clock for an external audio component at 256 times the sampling frequency. 

# 3.24 USB Type-C Power Delivery controller 

The device embeds two controllers (UCPD1 and UCPD2) compliant with USB Type-C Rev. 1.2 and USB Power Delivery Rev. 3.0 specifications. The controllers use specific I/Os supporting the USB Type-C and USB Power Delivery requirements, featuring: 

• USB Type-C pull-up (Rp, all values) and pull-down (Rd) resistors 

• “Dead battery” support 

• USB Power Delivery message transmission and reception 

• FRS (fast role swap) support 

Table 10. SPI/I2S implementation SPI features (1)              

> 1. X = supported.
> SPI1 SPI2
> Hardware CRC calculation XXRx/Tx FIFO XXNSS pulse mode XXI2S mode X-TI mode XXDS12232 Rev 5 35/143

STM32G071x8/xB Functional overview 

> 35

The digital controller handles notably: 

• USB Type-C level detection with de-bounce, generating interrupts 

• FRS detection, generating an interrupt 

• byte-level interface for USB Power Delivery payload, generating interrupts (DMA compatible) 

• USB Power Delivery timing dividers (including a clock pre-scaler) 

• CRC generation/checking 

• 4b5b encode/decode 

• ordered sets (with a programmable ordered set mask at receive) 

• frequency recovery in receiver during preamble The interface offers low-power operation compatible with Stop mode, maintaining the capacity to detect incoming USB Power Delivery messages and FRS signaling. 

# 3.25 Development support 3.25.1 Serial wire debug port (SW-DP) 

An Arm SW-DP interface is provided to allow a serial wire debugging tool to be connected to the MCU. Pinouts, pin description and alternate functions STM32G071x8/xB 

36/143 DS12232 Rev 5 

# 4 Pinouts, pin description and alternate functions 

The devices housed in 28-pin and 32-pin packages come in two variants - “GP” and “N” (the latter with ordering code having N behind the temperature range digit). Refer to Table 2: Features and peripheral counts for differences. 

Figure 3. STM32G071Ex WLCSP25 ballout 

> MSv47938V2

1 2 3 4 5ABCDEPA15 PA14-BOOT0 PB5 PB7 PC14-OSC32 _IN PA12 [PA10] PA13 PB6 PB8 PC15-OSC32 _OUT PA11 [PA9] PA6 PA3 PA0 VDD/ VDDA PA8 PA7 PA4 PA1 VSS/ VSSA PB1 PB0 PA5 PA2 PF2 -NRST Top view DS12232 Rev 5 37/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

48 

Figure 4. STM32G071GxU UFQFPN28 pinout 

> MSv42122V2 PA2 PA3 PA4 PA5 PA6 PA7 PB0

PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA14-BOOT0 PA13 PA12 [PA10] PA11 [PA9] PC6 PA8 PB15 PD0 PD1 PD2 PD3 PB6 PB7 PB8 

## Top view 

## UFQFPN28 123456721 20 19 18 17 16 15 25 23 28 27 26 24 22 11 13 8910 12 14 

> MSv39713V4 PA2 PA3 PA4 PA5 PA6 PA7 PB0

PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA14-BOOT0 PA13 PA12 [PA10] PA11 [PA9] PC6 PA8 PB1 PA15 PB3 PB4 PB5 PB6 PB7 PB8 

## Top view 

## UFQFPN28 123456721 20 19 18 17 16 15 25 23 28 27 26 24 22 11 13 8910 12 14 

GP version N version (_GxUxN) (_GxU) Pinouts, pin description and alternate functions STM32G071x8/xB 

38/143 DS12232 Rev 5 

Figure 5. STM32G071KxT LQFP32 pinout 

MSv42120V1 PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB9 PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA13 PA12 [PA10] PA11 [PA9] PA10 PC6 PA9 PA8 PB15 PA14-BOOT0 PD0 PD1 PD2 PD3 PB6 PB7 PB8 

## Top view 

## LQFP32 1234567824 23 22 21 20 19 18 17 29 27 25 32 31 30 28 26 12 14 16 910 11 13 15 

MSv39712V3 PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB9 PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA13 PA12 [PA10] PA11 [PA9] PA10 PC6 PA9 PA8 PB2 PA14-BOOT0 PA15 PB3 PB4 PB5 PB6 PB7 PB8 

## Top view 

## LQFP32 1234567824 23 22 21 20 19 18 17 29 27 25 32 31 30 28 26 12 14 16 910 11 13 15 

GP version N version (_KxTxN) (_KxT) DS12232 Rev 5 39/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

48 

Figure 6. STM32G071KxU UFQFPN32 pinout 

> MSv42121V1

Exposed pad PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB9 PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA13 PA12 [PA10] PA11 [PA9] PA10 PC6 PA9 PA8 PB15 PA14-BOOT0 PD0 PD1 PD2 PD3 PB6 PB7 PB8 

## Top view 

Exposed pad UFQFPN32 1234567824 23 22 21 20 19 18 17 29 27 25 32 31 30 28 26 12 14 16 910 11 13 15 VSS 

> MSv39715V3

Exposed pad PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB9 PC14-OSC32_IN PC15-OSC32_OUT VDD/VDDA VSS/VSSA PF2-NRST PA0 PA1 PA13 PA12 [PA10] PA11 [PA9] PA10 PC6 PA9 PA8 PB2 PA14-BOOT0 PA15 PB3 PB4 PB5 PB6 PB7 PB8 

## Top view 

Exposed pad UFQFPN32 1234567824 23 22 21 20 19 18 17 29 27 25 32 31 30 28 26 12 14 16 910 11 13 15 VSS 

GP version N version (_KxUxN) (_KxU) Pinouts, pin description and alternate functions STM32G071x8/xB 

40/143 DS12232 Rev 5 

Figure 7. STM32G071CxT LQFP48 pinout Figure 8. STM32G071CxU UFQFPN48 pinout 

MSv39711V3 PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB2 PB10 PB11 PB12 PC13 PC14-OSC32_IN PC15-OSC32_OUT VBAT VREF+ VDD/VDDA VSS/VSSA PF2-NRST PF0-OSC_IN PF1-OSC_OUT PA0 PA1 PA14-BOOT0 PA13 PA12 [PA10] PA11 [PA9] PA10 PC7 PC6 PA9 PA8 PB15 PB14 PB13 PA15 PD0 PD1 PD2 PD3 PB3 PB4 PB5 PB6 PB7 PB8 PB9 Top view 

## LQFP48 12345678910 11 12 36 35 34 33 32 31 30 29 28 27 26 25 39 37 40 38 45 43 41 48 47 46 44 42 22 24 21 23 16 18 20 13 14 15 17 19 

Exposed pad MSv39714V3 

## Top view 

Exposed pad UFQFPN48 12345678910 11 12 36 35 34 33 32 31 30 29 28 27 26 25 39 37 40 38 45 43 41 48 47 46 44 42 22 24 21 23 16 18 20 13 14 15 17 19 VSS PA2 PA3 PA4 PA5 PA6 PA7 PB0 PB1 PB2 PB10 PB11 PB12 PC13 PC14-OSC32_IN PC15-OSC32_OUT VBAT VREF+ VDD/VDDA VSS/VSSA PF2-NRST PF0-OSC_IN PF1-OSC_OUT PA0 PA1 PA14-BOOT0 PA13 PA12 [PA10] PA11 [PA9] PA10 PC7 PC6 PA9 PA8 PB15 PB14 PB13 PA15 PD0 PD1 PD2 PD3 PB3 PB4 PB5 PB6 PB7 PB8 PB9 DS12232 Rev 5 41/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

48 

Figure 9. STM32G071RxT LQFP64 pinout Figure 10. STM32G071RxI UFBGA64 ballout 

MSv39710V3 PA0 PA1 PA2 PA3 PA4 PA5 PA6 PA7 PC4 PC5 PB0 PB1 PB2 PB10 PB11 PB12 PC11 PC12 PC13 PC14-OSC32_IN PC15-OSC32_OUT VBAT VREF+ VDD/VDDA VSS/VSSA PF2-NRST PF0-OSC_IN PF1-OSC_OUT PC0 PC1 PC2 PC3 PC8 PA15 PA14-BOOT0 PA13 PA12 [PA10] PA11 [PA9] PA10 PD9 PD8 PC7 PC6 PA9 PA8 PB15 PB14 PB13 PC9 PD0 PD1 PD2 PD3 PD4 PD5 PD6 PB3 PB4 PB5 PB6 PB7 PB8 PB9 PC10 

## Top view 

## LQFP64 1345678910 11 12 13 14 15 16 248 46 45 44 43 42 41 40 39 38 37 36 35 34 33 47 55 53 52 51 50 49 56 54 61 59 57 64 63 62 60 58 26 28 29 30 31 32 25 27 20 22 24 17 18 19 21 23 

MSv47971V1 ABCDEVDD/ VDDA VREF+ VBAT PB5 PD3 VSS/ VSSA PF2-NRST PC0 PA7 PC7 PF0-OSC_I NPC1 PA3 PA6 PB0 PF1-OSC_ OUT PC2 PA2 PA5 PB1 PC3 PA0 PA1 PA4 PC4 PC11 PC10 PB7 PB6 PD6 PC15-OSC32 _OUT PC12 PB8 PB3 PD5 PC14-OSC32 _IN PC13 PB9 PB4 PD4 PA10 PA13 PD9 PA9 PC6 PD8 PB14 PB15 PA8 PB10 PB12 PB13 PC5 PB2 PB11 PD2 PD0 PC8 PD1 PC9 PA12 [PA10] PA15 PA14-BOOT0 PA11 [PA9] 1 2 3 4 5 6 7 8FGHPinouts, pin description and alternate functions STM32G071x8/xB 

42/143 DS12232 Rev 5 

Table 11. Terms and symbols used in Pin assignment and description table Column Symbol Definition 

Pin name Terminal name corresponds to its by-default function at reset, unless otherwise specified in parenthesis under the pin name. Pin type S Supply pin I Input only pin I/O Input / output pin I/O structure FT 5 V tolerant I/O TT 3.6 V tolerant I/O RST Reset pin with embedded weak pull-up resistor 

Options for TT or FT I/Os 

_f I/O, Fm+ capable _a I/O, with analog switch function _c I/O, USB Type-C PD capable _d I/O, USB Type-C PD Dead Battery function Note Upon reset, all I/Os are set as analog inputs, unless otherwise specified. Pin functions Alternate functions Functions selected through GPIOx_AFR registers Additional functions Functions directly selected/enabled through peripheral registers 

Table 12. Pin assignment and description Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64                                      

> ------A1 1PC11 I/O FT -USART3_RX, USART4_RX, TIM1_CH4 -------B2 2PC12 I/O FT -LPTIM1_IN1, UCPD1_FRSTX, TIM14_CH1 ------1C2 3PC13 I/O FT (1)(2) TIM1_BKIN TAMP_IN1,RTC_TS, RTC_OUT1,WKUP2

DS12232 Rev 5 43/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

> 48

- - - - - 2 C1 4PC14-OSC32_IN (PC14) I/O FT (1)(2) TIM1_BKIN2 OSC32_IN A5 1 1 2 2 - - -PC14-OSC32_IN (PC14) I/O FT (1)(2) TIM1_BKIN2 OSC32_IN,OSC_IN B5 2 2 3 3 3 B1 5PC15-OSC32_OUT (PC15) I/O FT (1)(2) OSC32_EN, OSC_EN, TIM15_BKIN OSC32_OUT - - - - - 4 D3 6 VBAT S - - - -- - - - - 5 D2 7 VREF+ S - - - VREF_OUT C5 3 3 4 4 6 D1 8 VDD/VDDA S - - - -D5 4 4 5 5 7 E1 9 VSS/VSSA S - - - -- - - - - 8 F1 10 PF0-OSC_IN (PF0) I/O FT - TIM14_CH1 OSC_IN - - - - - 9 G1 11 PF1-OSC_OUT (PF1) I/O FT - OSC_EN, TIM15_CH1N OSC_OUT E5 5 5 6 6 10 E2 12 PF2 - NRST I/O RST, FT (3) MCO NRST - - - - - - E3 13 PC0 I/O FT - LPTIM1_IN1, LPUART1_RX, LPTIM2_IN1 -- - - - - - F2 14 PC1 I/O FT - LPTIM1_OUT, LPUART1_TX, TIM15_CH1 -- - - - - - G2 15 PC2 I/O FT - LPTIM1_IN2, SPI2_MISO, TIM15_CH2 -- - - - - - H1 16 PC3 I/O FT - LPTIM1_ETR, SPI2_MOSI, LPTIM2_ETR -C4 6 6 7 7 11 H2 17 PA0 I/O FT_a -SPI2_SCK, USART2_CTS, TIM2_CH1_ETR, USART4_TX, LPTIM1_OUT, UCPD2_FRSTX, COMP1_OUT COMP1_INM, ADC_IN0, TAMP_IN2,WKUP1 

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 Pinouts, pin description and alternate functions STM32G071x8/xB 

44/143 DS12232 Rev 5 

D4 7 7 8 8 12 H3 18 PA1 I/O FT_a -SPI1_SCK/I2S1_CK, USART2_RTS_DE_CK, TIM2_CH2, USART4_RX, TIM15_CH1N, I2C1_SMBA, EVENTOUT COMP1_INP, ADC_IN1 E4 8 8 9 9 13 G3 19 PA2 I/O FT_a -SPI1_MOSI/I2S1_SD, USART2_TX, TIM2_CH3, UCPD1_FRSTX, TIM15_CH1, LPUART1_TX, COMP2_OUT COMP2_INM, ADC_IN2, WKUP4,LSCO C3 9 9 10 10 14 F3 20 PA3 I/O FT_a -SPI2_MISO, USART2_RX, TIM2_CH4, UCPD2_FRSTX, TIM15_CH2, LPUART1_RX, EVENTOUT COMP2_INP, ADC_IN3 - - - - - 15 H4 21 PA4 I/O TT_a -SPI1_NSS/I2S1_WS, SPI2_MOSI, TIM14_CH1, LPTIM2_OUT, UCPD2_FRSTX, EVENTOUT ADC_IN4, DAC_OUT1, RTC_OUT2 D3 10 10 11 11 - - - PA4 I/O TT_a -SPI1_NSS/I2S1_WS, SPI2_MOSI, TIM14_CH1, LPTIM2_OUT, UCPD2_FRSTX, EVENTOUT ADC_IN4, DAC_OUT1, TAMP_IN1,RTC_TS, RTC_OUT1,WKUP2 E3 11 11 12 12 16 G4 22 PA5 I/O TT_a -SPI1_SCK/I2S1_CK, CEC, TIM2_CH1_ETR, USART3_TX, LPTIM2_ETR, UCPD1_FRSTX, EVENTOUT ADC_IN5, DAC_OUT2 C2 12 12 13 13 17 F4 23 PA6 I/O FT_a -SPI1_MISO/I2S1_MCK, TIM3_CH1, TIM1_BKIN, USART3_CTS, TIM16_CH1, LPUART1_CTS, COMP1_OUT ADC_IN6 D2 13 13 14 14 18 E4 24 PA7 I/O FT_a -SPI1_MOSI/I2S1_SD, TIM3_CH2, TIM1_CH1N, TIM14_CH1, TIM17_CH1, UCPD1_FRSTX, COMP2_OUT ADC_IN7 - - - - - - H5 25 PC4 I/O FT_a - USART3_TX, USART1_TX, TIM2_CH1_ETR COMP1_INM, ADC_IN17 

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 DS12232 Rev 5 45/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

> 48

- - - - - - H6 26 PC5 I/O FT_a - USART3_RX, USART1_RX, TIM2_CH2 COMP1_INP, ADC_IN18, WKUP5 E2 14 - 15 15 19 F5 27 PB0 I/O FT_a -SPI1_NSS/I2S1_WS, TIM3_CH3, TIM1_CH2N, USART3_RX, LPTIM1_OUT, UCPD1_FRSTX, COMP1_OUT ADC_IN8 - - 14 - - - - - PB0 I/O FT_da (4) SPI1_NSS/I2S1_WS, TIM3_CH3, TIM1_CH2N, USART3_RX, LPTIM1_OUT, UCPD1_FRSTX, COMP1_OUT UCPD1_DBCC2, ADC_IN8 E1 15 - 16 16 20 G5 28 PB1 I/O FT_a -TIM14_CH1, TIM3_CH4, TIM1_CH3N, USART3_RTS_DE_CK, LPTIM2_IN1, LPUART1_RTS_DE, EVENTOUT COMP1_INM, ADC_IN9 - - - 17 - 21 H7 29 PB2 I/O FT_a - SPI2_MISO, USART3_TX, LPTIM1_OUT, EVENTOUT COMP1_INP, ADC_IN10 - - - - - 22 G6 30 PB10 I/O FT_fa -CEC, LPUART1_RX, TIM2_CH3, USART3_TX, SPI2_SCK, I2C2_SCL, COMP1_OUT ADC_IN11 - - - - - 23 H8 31 PB11 I/O FT_fa -SPI2_MOSI, LPUART1_TX, TIM2_CH4, USART3_RX, I2C2_SDA, COMP2_OUT ADC_IN15 - - - - - 24 G7 32 PB12 I/O FT_a -SPI2_NSS, LPUART1_RTS_DE, TIM1_BKIN, TIM15_BKIN, UCPD2_FRSTX, EVENTOUT ADC_IN16 - - - - - 25 G8 33 PB13 I/O FT_f -SPI2_SCK, LPUART1_CTS, TIM1_CH1N, USART3_CTS, TIM15_CH1N, I2C2_SCL, EVENTOUT -

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 Pinouts, pin description and alternate functions STM32G071x8/xB 

46/143 DS12232 Rev 5 

- - - - - 26 F6 34 PB14 I/O FT_f -SPI2_MISO, UCPD1_FRSTX, TIM1_CH2N, USART3_RTS_DE_CK, TIM15_CH1, I2C2_SDA, EVENTOUT -- - 15 - 17 27 F7 35 PB15 I/O FT_c (4) SPI2_MOSI, TIM1_CH3N, TIM15_CH1N, TIM15_CH2, EVENTOUT UCPD1_CC2, RTC_REFIN, D1 16 16 18 18 28 F8 36 PA8 I/O FT_c (4) MCO, SPI2_NSS, TIM1_CH1, LPTIM2_OUT, EVENTOUT UCPD1_CC1 - - - 19 19 29 E6 37 PA9 I/O FT_fd (4) MCO, USART1_TX, TIM1_CH2, SPI2_MISO, TIM15_BKIN, I2C1_SCL, EVENTOUT UCPD1_DBCC1 - 17 - 20 20 30 E7 38 PC6 I/O FT - UCPD1_FRSTX, TIM3_CH1, TIM2_CH3 -- - 17 - - - - - PC6 I/O FT_d (4) UCPD1_FRSTX, TIM3_CH1, TIM2_CH3 UCPD1_DBCC1 - - - - - 31 E5 39 PC7 I/O FT - UCPD2_FRSTX, TIM3_CH2, TIM2_CH4 -- - - - - - E8 40 PD8 I/O FT -USART3_TX, SPI1_SCK/I2S1_CK, LPTIM1_OUT -- - - - - - D8 41 PD9 I/O FT -USART3_RX, SPI1_NSS/I2S1_WS, TIM1_BKIN2 -- - - 21 21 32 D6 42 PA10 I/O FT_fd (4) SPI2_MOSI, USART1_RX, TIM1_CH3, TIM17_BKIN, I2C1_SDA, EVENTOUT UCPD1_DBCC2 C1 18 18 22 22 33 C8 43 PA11 [PA9] (5) I/O FT_f -SPI1_MISO/I2S1_MCK, USART1_CTS, TIM1_CH4, TIM1_BKIN2, I2C2_SCL, COMP1_OUT -B1 19 19 23 23 34 B8 44 PA12 [PA10] (5) I/O FT_f -SPI1_MOSI/I2S1_SD, USART1_RTS_DE_CK, TIM1_ETR, I2S_CKIN, I2C2_SDA, COMP2_OUT -

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 DS12232 Rev 5 47/143 

STM32G071x8/xB Pinouts, pin description and alternate functions 

> 48

B2 20 20 24 24 35 D7 45 PA13 I/O FT (6) SWDIO, IR_OUT, EVENTOUT -A2 21 21 25 25 36 C7 46 PA14-BOOT0 I/O FT (6) SWCLK, USART2_TX, EVENTOUT BOOT0 A1 22 - 26 - 37 C6 47 PA15 I/O FT -SPI1_NSS/I2S1_WS, USART2_RX, TIM2_CH1_ETR, USART4_RTS_DE_CK, USART3_RTS_DE_CK, EVENTOUT -- - - - - - A8 48 PC8 I/O FT - UCPD2_FRSTX, TIM3_CH3, TIM1_CH1 -- - - - - - B7 49 PC9 I/O FT - I2S_CKIN, TIM3_CH4, TIM1_CH2 -- - 22 - 26 38 A7 50 PD0 I/O FT_c (4) EVENTOUT, SPI2_NSS, TIM16_CH1 UCPD2_CC1 - - 23 - 27 39 B6 51 PD1 I/O FT_d (4) EVENTOUT, SPI2_SCK, TIM17_CH1 UCPD2_DBCC1 - - 24 - 28 40 A6 52 PD2 I/O FT_c (4) USART3_RTS_DE_CK, TIM3_ETR, TIM1_CH1N UCPD2_CC2 - - 25 - 29 41 D5 53 PD3 I/O FT_d (4) USART2_CTS, SPI2_MISO, TIM1_CH2N UCPD2_DBCC2 - - - - - - C5 54 PD4 I/O FT - USART2_RTS_DE_CK, SPI2_MOSI, TIM1_CH3N -- - - - - - B5 55 PD5 I/O FT -USART2_TX, SPI1_MISO/I2S1_MCK, TIM1_BKIN -- - - - - - A5 56 PD6 I/O FT -USART2_RX, SPI1_MOSI/I2S1_SD, LPTIM2_OUT -- 23 - 27 - 42 B4 57 PB3 I/O FT_a -SPI1_SCK/I2S1_CK, TIM1_CH2, TIM2_CH2, USART1_RTS_DE_CK, EVENTOUT COMP2_INM - 24 - 28 - 43 C4 58 PB4 I/O FT_a -SPI1_MISO/I2S1_MCK, TIM3_CH1, USART1_CTS, TIM17_BKIN, EVENTOUT COMP2_INP 

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 Pinouts, pin description and alternate functions STM32G071x8/xB 

48/143 DS12232 Rev 5 

A3 25 - 29 - 44 D4 59 PB5 I/O FT -SPI1_MOSI/I2S1_SD, TIM3_CH2, TIM16_BKIN, LPTIM1_IN1, I2C1_SMBA, COMP2_OUT WKUP6 B3 26 26 30 30 45 A4 60 PB6 I/O FT_fa -USART1_TX, TIM1_CH3, TIM16_CH1N, SPI2_MISO, LPTIM1_ETR, I2C1_SCL, EVENTOUT COMP2_INP A4 27 27 31 31 46 A3 61 PB7 I/O FT_fa -USART1_RX, SPI2_MOSI, TIM17_CH1N, USART4_CTS, LPTIM1_IN2, I2C1_SDA, EVENTOUT COMP2_INM, PVD_IN B4 28 28 32 32 47 B3 62 PB8 I/O FT_f -CEC, SPI2_SCK, TIM16_CH1, USART3_TX, TIM15_BKIN, I2C1_SCL, EVENTOUT -- - - 1 1 48 C3 63 PB9 I/O FT_f -IR_OUT, UCPD2_FRSTX, TIM17_CH1, USART3_RX, SPI2_NSS, I2C1_SDA, EVENTOUT -- - - - - - A2 64 PC10 I/O FT - USART3_TX, USART4_TX, TIM1_CH3 -1. PC13, PC14 and PC15 are supplied through the power switch. Since the switch only sinks a limited amount of current (3 mA), the use of GPIOs PC13 to PC15 in output mode is limited: 

- The speed should not exceed 2 MHz with a maximum load of 30 pF 

- These GPIOs must not be used as current sources (for example to drive a LED). 2. After an RTC domain power-up, PC13, PC14 and PC15 operate as GPIOs. Their function then depends on the content of the RTC registers. The RTC registers are not reset upon system reset. For details on how to manage these GPIOs, refer to the RTC domain and RTC register descriptions in the RM0444 reference manual. 3. RST I/O structure when the PF2-NRST pin is configured as reset (input or input/output mode), FT I/O structure when the PF2-NRST pin is configured as GPIO. 4. Upon reset, a pull-down resistor might be present on PA8, PB15, PD0, or PD2, depending on the voltage level on PA9/PC6, PA10/PB0, PD1, and PD3, respectively. In order to disable this resistor, strobe the UCPDx_STROBE bit of the SYSCFG_CFGR1 register during start-up sequence. 5. Pins PA9/PA10 can be remapped in place of pins PA11/PA12 (default mapping), using SYSCFG_CFGR1 register. 6. Upon reset, these pins are configured as SW debug alternate functions, and the internal pull-up on PA13 pin and the internal pull-down on PA14 pin are activated. 

Table 12. Pin assignment and description (continued) Pin number Pin name (function upon reset) Pin type I/O structure Note  Alternate functions Additional functions WLCSP25 UFQFPN28 - GP UFQFPN28 - N LQFP32 / UFQFPN32 - GP LQFP32 / UFQFPN32 - N LQFP48 / UFQFPN48 UFBGA64 LQFP64 STM32G071x8/xB 

DS12232 Rev 5 49/143 

> Table 13. Port A alternate function mapping Port  AF0  AF1  AF2  AF3  AF4  AF5  AF6  AF7
> PA0  SPI2_SCK  USART2_CTS  TIM2_CH1_ETR  - USART4_TX  LPTIM1_OUT  UCPD2_FRSTX  COMP1_OUT PA1  SPI1_SCK/ I2S1_CK USART2_RTS _DE_CK  TIM2_CH2  - USART4_RX  TIM15_CH1N  I2C1_SMBA  EVENTOUT PA2  SPI1_MOSI/ I2S1_SD  USART2_TX  TIM2_CH3  - UCPD1_FRSTX  TIM15_CH1  LPUART1_TX  COMP2_OUT PA3  SPI2_MISO  USART2_RX  TIM2_CH4  - UCPD2_FRSTX  TIM15_CH2  LPUART1_RX  EVENTOUT PA4  SPI1_NSS/ I2S1_WS  SPI2_MOSI  - - TIM14_CH1  LPTIM2_OUT  UCPD2_FRSTX  EVENTOUT PA5  SPI1_SCK/ I2S1_CK  CEC  TIM2_CH1_ETR  - USART3_TX  LPTIM2_ETR  UCPD1_FRSTX  EVENTOUT PA6  SPI1_MISO/ I2S1_MCK  TIM3_CH1  TIM1_BKIN  - USART3_CTS  TIM16_CH1  LPUART1_CTS  COMP1_OUT PA7  SPI1_MOSI/ I2S1_SD  TIM3_CH2  TIM1_CH1N  - TIM14_CH1  TIM17_CH1  UCPD1_FRSTX  COMP2_OUT PA8  MCO  SPI2_NSS  TIM1_CH1  - - LPTIM2_OUT  - EVENTOUT PA9  MCO  USART1_TX  TIM1_CH2  - SPI2_MISO  TIM15_BKIN  I2C1_SCL  EVENTOUT PA10  SPI2_MOSI  USART1_RX  TIM1_CH3  - - TIM17_BKIN  I2C1_SDA  EVENTOUT PA11  SPI1_MISO/ I2S1_MCK  USART1_CTS  TIM1_CH4  - - TIM1_BKIN2  I2C2_SCL  COMP1_OUT PA12  SPI1_MOSI/ I2S1_SD USART1_RTS _DE_CK  TIM1_ETR  - - I2S_CKIN  I2C2_SDA  COMP2_OUT PA13  SWDIO  IR_OUT  - - - - - EVENTOUT PA14  SWCLK  USART2_TX  - - - - - EVENTOUT PA15  SPI1_NSS/ I2S1_WS  USART2_RX  TIM2_CH1_ETR  - USART4_RTS _DE_CK USART3_RTS _DE_CK  - EVENTOUT

STM32G071x8/xB 

50/143 DS12232 Rev 5 

> Table 14. Port B alternate function mapping Port  AF0  AF1  AF2  AF3  AF4  AF5  AF6  AF7
> PB0  SPI1_NSS/ I2S1_WS  TIM3_CH3  TIM1_CH2N  - USART3_RX  LPTIM1_OUT  UCPD1_FRSTX  COMP1_OUT PB1  TIM14_CH1  TIM3_CH4  TIM1_CH3N  - USART3_RTS _DE_CK  LPTIM2_IN1  LPUART1_RTS _DE  EVENTOUT PB2  - SPI2_MISO  - - USART3_TX  LPTIM1_OUT  - EVENTOUT PB3  SPI1_SCK/ I2S1_CK  TIM1_CH2  TIM2_CH2  - USART1_RTS _DE_CK  - - EVENTOUT PB4  SPI1_MISO/ I2S1_MCK  TIM3_CH1  - - USART1_CTS  TIM17_BKIN  - EVENTOUT PB5  SPI1_MOSI/ I2S1_SD  TIM3_CH2  TIM16_BKIN  - - LPTIM1_IN1  I2C1_SMBA  COMP2_OUT PB6  USART1_TX  TIM1_CH3  TIM16_CH1N  - SPI2_MISO  LPTIM1_ETR  I2C1_SCL  EVENTOUT PB7  USART1_RX  SPI2_MOSI  TIM17_CH1N  - USART4_CTS  LPTIM1_IN2  I2C1_SDA  EVENTOUT PB8  CEC  SPI2_SCK  TIM16_CH1  - USART3_TX  TIM15_BKIN  I2C1_SCL  EVENTOUT PB9  IR_OUT  UCPD2_FRSTX  TIM17_CH1  - USART3_RX  SPI2_NSS  I2C1_SDA  EVENTOUT PB10  CEC  LPUART1_RX  TIM2_CH3  - USART3_TX  SPI2_SCK  I2C2_SCL  COMP1_OUT PB11  SPI2_MOSI  LPUART1_TX  TIM2_CH4  - USART3_RX  - I2C2_SDA  COMP2_OUT PB12  SPI2_NSS  LPUART1_RTS _DE  TIM1_BKIN  - - TIM15_BKIN  UCPD2_FRSTX  EVENTOUT PB13  SPI2_SCK  LPUART1_CTS  TIM1_CH1N  - USART3_CTS  TIM15_CH1N  I2C2_SCL  EVENTOUT PB14  SPI2_MISO  UCPD1_FRSTX  TIM1_CH2N  - USART3_RTS _DE_CK  TIM15_CH1  I2C2_SDA  EVENTOUT PB15  SPI2_MOSI  - TIM1_CH3N  - TIM15_CH1N  TIM15_CH2  - EVENTOUT

STM32G071x8/xB 

DS12232 Rev 5 51/143 

> Table 15. Port C alternate function mapping Port  AF0  AF1  AF2  AF3  AF4  AF5  AF6  AF7
> PC0  LPTIM1_IN1  LPUART1_RX  LPTIM2_IN1  - - - - -PC1  LPTIM1_OUT  LPUART1_TX  TIM15_CH1  - - - - -PC2  LPTIM1_IN2  SPI2_MISO  TIM15_CH2  - - - - -PC3  LPTIM1_ETR  SPI2_MOSI  LPTIM2_ETR  - - - - -PC4  USART3_TX  USART1_TX  TIM2_CH1_ETR  - - - - -PC5  USART3_RX  USART1_RX  TIM2_CH2  - - - - -PC6  UCPD1_FRSTX  TIM3_CH1  TIM2_CH3  - - - - -PC7  UCPD2_FRSTX  TIM3_CH2  TIM2_CH4  - - - - -PC8  UCPD2_FRSTX  TIM3_CH3  TIM1_CH1  - - - - -PC9  I2S_CKIN  TIM3_CH4  TIM1_CH2  - - - - -PC10  USART3_TX  USART4_TX  TIM1_CH3  - - - - -PC11  USART3_RX  USART4_RX  TIM1_CH4  - - - - -PC12  LPTIM1_IN1  UCPD1_FRSTX  TIM14_CH1  - - - - -PC13  - - TIM1_BKIN  - - - - -PC14  - - TIM1_BKIN2  - - - - -PC15  OSC32_EN  OSC_EN  TIM15_BKIN  - - - - -

STM32G071x8/xB 

52/143 DS12232 Rev 5  

> *
> Table 16. Port D alternate function mapping Port  AF0  AF1  AF2  AF3  AF4  AF5  AF6  AF7
> PD0  EVENTOUT  SPI2_NSS  TIM16_CH1  - - - - -PD1  EVENTOUT  SPI2_SCK  TIM17_CH1  - - - - -PD2  USART3_RTS _DE_CK  TIM3_ETR  TIM1_CH1N  - - - - -PD3  USART2_CTS  SPI2_MISO  TIM1_CH2N  - - - - -PD4  USART2_RTS _DE_CK  SPI2_MOSI  TIM1_CH3N  - - - - -PD5  USART2_TX  SPI1_MISO/ I2S1_MCK  TIM1_BKIN  - - - - -PD6  USART2_RX  SPI1_MOSI/ I2S1_SD  LPTIM2_OUT  - - - - -PD8  USART3_TX  SPI1_SCK/ I2S1_CK  LPTIM1_OUT  - - - - -PD9  USART3_RX  SPI1_NSS/ I2S1_WS  TIM1_BKIN2  - - - - -
> Table 17. Port F alternate function mapping Port  AF0  AF1  AF2  AF3  AF4  AF5  AF6  AF7
> PF0  - - TIM14_CH1  - - - - -PF1  OSC_EN  - TIM15_CH1N  - - - - -PF2  MCO  - - - - - - -DS12232 Rev 5 53/143

STM32G071x8/xB Electrical characteristics 

> 110

# 5 Electrical characteristics 5.1 Parameter conditions 

Unless otherwise specified, all voltages are referenced to V SS .Parameter values defined at temperatures or in temperature ranges out of the ordering information scope are to be ignored. Packages used for characterizing certain electrical parameters may differ from the commercial packages as per the ordering information. 

## 5.1.1 Minimum and maximum values 

Unless otherwise specified, the minimum and maximum values are guaranteed in the worst conditions of ambient temperature, supply voltage and frequencies by tests in production on 100% of the devices with an ambient temperature at TA = 25 °C and TA = TA(max) (given by the selected temperature range). Data based on characterization results, design simulation and/or technology characteristics are indicated in the table footnotes and are not tested in production. Based on characterization, the minimum and maximum values refer to sample tests and represent the mean value plus or minus three times the standard deviation (mean ±3 σ). 

## 5.1.2 Typical values 

Unless otherwise specified, typical data are based on T A = 25 °C, V DD = V DDA = 3 V. They are given only as design guidelines and are not tested. Typical ADC accuracy values are determined by characterization of a batch of samples from a standard diffusion lot over the full temperature range, where 95% of the devices have an error less than or equal to the value indicated (mean ±2 σ). 

## 5.1.3 Typical curves 

Unless otherwise specified, all typical curves are given only as design guidelines and are not tested. 

## 5.1.4 Loading capacitor 

The loading conditions used for pin parameter measurement are shown in Figure 11 .

## 5.1.5 Pin input voltage 

The input voltage measurement on a pin of the device is described in Figure 12 .

Figure 11. Pin loading conditions Figure 12. Pin input voltage 

> MCU pin C = 50 pF
> MCU pin VIN

Electrical characteristics STM32G071x8/xB 

54/143 DS12232 Rev 5 

## 5.1.6 Power supply scheme Figure 13. Power supply scheme 

1. Internally connected to VDDA on devices without VREF+ pin. 2. Only required when VREFBUF is used. 

Caution: Power supply pin pair (VDD/VDDA and VSS/VSSA) must be decoupled with filtering ceramic capacitors as shown above. These capacitors must be placed as close as possible to, or below, the appropriate pins on the underside of the PCB to ensure the good functionality of the device. 

> MSv47900V2

VDD Backup circuitry (LSE, RTC and backup registers) Kernel logic (CPU, digital and memories) Level shifter IO logic IN OUT Regulator GPIOs 1.55 V to 3.6 V 1 x 100 nF + 1 x 4.7 μF VDD/VDDA VBAT VCORE Power switch VDDIO1 ADC DAC COMPs VREFBUF VREF+ VREF-VSS VSSA VDDA VDD VSS/VSSA VREF 100 nF + 1 μF (2) VREF+ (1) DS12232 Rev 5 55/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.1.7 Current consumption measurement Figure 14. Current consumption measurement scheme 5.2 Absolute maximum ratings 

Stresses above the absolute maximum ratings listed in Table 18 , Table 19 and Table 20 

may cause permanent damage to the device. These are stress ratings only and functional operation of the device at these conditions is not implied. Exposure to maximum rating conditions for extended periods may affect device reliability. The device mission profile (application conditions) is compliant with the JEDEC JESD47 qualification standard. All voltages are defined with respect to V SS .

> MSv47901V1

IDDVBAT VBAT IDD VDD (VDDA) VBAT VDD/VDDA 

Table 18. Voltage characteristics Symbol Ratings Min Max Unit 

VDD External supply voltage -0.3 4.0 VVBAT External supply voltage on VBAT pin -0.3 4.0 VVREF+ External voltage on VREF+ pin -0.3 Min(V DD + 0.4, 4.0) VVIN (1) Input voltage on FT_xx pins except FT_c -0.3 VDD + 4.0 (2)(3) VInput voltage on FT_c pins -0.3 5.5 Input voltage on any other pin -0.3 4.0 1. Refer to Table 19 for the maximum allowed injected current values. 2. To sustain a voltage higher than 4 V the internal pull-up/pull-down resistors must be disabled. 3. When an FT_a pin is used by an analog peripheral such as ADC, the maximum VIN is 4 V. 

Table 19. Current characteristics Symbol Ratings Max Unit 

IVDD/VDDA Current into VDD/VDDA power pin (source) (1) 100 mA IVSS/VSSA Current out of VSS/VSSA ground pin (sink) (2) 100 mA IIO(PIN) Output current sunk by any I/O and control pin except FT_f 15 mA Output current sunk by any FT_f pin 20 Output current sourced by any I/O and control pin 15 Electrical characteristics STM32G071x8/xB 

56/143 DS12232 Rev 5 

# 5.3 Operating conditions 5.3.1 General operating conditions 

∑IIO(PIN) Total output current sunk by sum of all I/Os and control pins 80 mA Total output current sourced by sum of all I/Os and control pins 80 IINJ(PIN) (2) Injected current on a FT_xx pin -5 / NA (3) mA Injected current on a TT_a pin (4) -5 / 0 

∑|I INJ(PIN) | Total injected current (sum of all I/Os and control pins) (5) 25 mA 1. All main power (VDD/VDDA, VBAT) and ground (VSS/VSSA) pins must always be connected to the external power supplies, in the permitted range. 2. A positive injection is induced by V IN > V DDIO1 while a negative injection is induced by V IN < V SS . I INJ(PIN) must never be exceeded. Refer also to Table 18: Voltage characteristics for the maximum allowed input voltage values. 3. Positive injection is not possible on these I/Os and does not occur for input voltages lower than the specified maximum value. 4. On these I/Os, any current injection disturbs the analog performances of the device. 5. When several inputs are submitted to a current injection, the maximum ∑|I INJ(PIN) | is the absolute sum of the negative injected currents (instantaneous values). 

Table 19. Current characteristics (continued) Symbol Ratings Max Unit 

Table 20. Thermal characteristics Symbol Ratings Value Unit 

TSTG Storage temperature range -65 to +150 °C TJ Maximum junction temperature 150 °C 

Table 21. General operating conditions Symbol Parameter Conditions Min Max Unit 

fHCLK Internal AHB clock frequency - 0 64 MHz fPCLK Internal APB clock frequency - 0 64 VDD Standard operating voltage - 1.7 (1) 3.6 VVDDA Analog supply voltage For ADC and COMP operation 1.62 3.6 VFor DAC operation 1.8 3.6 For VREFBUF operation 2.4 3.6 VBAT Backup operating voltage - 1.55 3.6 VVIN I/O input voltage All except: RST, TT_xx, FT_c -0.3 Min(VDD + 3.6, 5.5) (2) VRST -0.3 VDD + 0.3 TT_xx -0.3 VDDA + 0.3 FT_c -0.3 5.0 (2) DS12232 Rev 5 57/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.2 Operating conditions at power-up / power-down 

The parameters given in Table 22 are derived from tests performed under the ambient temperature condition summarized in Table 21 .

## 5.3.3 Embedded reset and power control block characteristics 

The parameters given in Table 23 are derived from tests performed under the ambient temperature conditions summarized in Table 21: General operating conditions .TA Ambient temperature (3) Suffix 6 (4) -40 85 °C Suffix 7 (4) -40 105 Suffix 3 (4) -40 125 TJ Junction temperature Suffix 6 (4) -40 105 °C Suffix 7 (4) -40 125 Suffix 3 (4) -40 130 1. When RESET is released functionality is guaranteed down to V PDR min. 2. For operation with voltage higher than V DD +0.3 V, the internal pull-up and pull-down resistors must be disabled. 3. The TA(max) applies to PD(max). At PD < PD(max) the ambient temperature is allowed to go higher than TA(max) provided that the junction temperature T J does not exceed T J(max). Refer to Section 6.10: Thermal characteristics .4. Temperature range digit in the order code. See Section 7: Ordering information .

Table 21. General operating conditions (continued) Symbol Parameter Conditions Min Max Unit 

Table 22. Operating conditions at power-up / power-down Symbol Parameter Conditions Min Max Unit 

tVDD VDD slew rate VDD rising - ∞ μs/V VDD falling; ULPEN = 0 10 ∞

VDD falling; ULPEN = 1 100 ∞ ms/V 

Table 23. Embedded reset and power control block characteristics Symbol Parameter Conditions (1) Min Typ Max Unit 

tRSTTEMPO (2) POR temporization when VDD crosses VPOR VDD rising - 250 400 μsVPOR (2) Power-on reset threshold - 1.62 1.66 1.70 VVPDR (2) Power-down reset threshold - 1.60 1.64 1.69 VVBOR1 Brownout reset threshold 1 VDD rising 2.05 2.10 2.18 VVDD falling 1.95 2.00 2.08 VBOR2 Brownout reset threshold 2 VDD rising 2.20 2.31 2.38 VVDD falling 2.10 2.21 2.28 VBOR3 Brownout reset threshold 3 VDD rising 2.50 2.62 2.68 VVDD falling 2.40 2.52 2.58 Electrical characteristics STM32G071x8/xB 

58/143 DS12232 Rev 5 

## 5.3.4 Embedded voltage reference 

The parameters given in Table 24 are derived from tests performed under the ambient temperature and supply voltage conditions summarized in Table 21: General operating conditions .VBOR4 Brownout reset threshold 4 VDD rising 2.80 2.91 3.00 VVDD falling 2.70 2.81 2.90 VPVD0 Programmable voltage detector threshold 0 VDD rising 2.05 2.15 2.22 VVDD falling 1.95 2.05 2.12 VPVD1 PVD threshold 1 VDD rising 2.20 2.30 2.37 VVDD falling 2.10 2.20 2.27 VPVD2 PVD threshold 2 VDD rising 2.35 2.46 2.54 VVDD falling 2.25 2.36 2.44 VPVD3 PVD threshold 3 VDD rising 2.50 2.62 2.70 VVDD falling 2.40 2.52 2.60 VPVD4 PVD threshold 4 VDD rising 2.65 2.74 2.87 VVDD falling 2.55 2.64 2.77 VPVD5 PVD threshold 5 VDD rising 2.80 2.91 3.03 VVDD falling 2.70 2.81 2.93 VPVD6 PVD threshold 6 VDD rising 2.90 3.01 3.14 VVDD falling 2.80 2.91 3.04 Vhyst_POR_PDR Hysteresis of VPOR and VPDR Hysteresis in continuous mode - 20 -mV Hysteresis in other mode - 30 -Vhyst_BOR_PVD Hysteresis of VBORx and VPVDx - - 100 - mV IDD(BOR_PVD) (2) BOR and PVD consumption - - 1.1 1.6 μA 1. Continuous mode means Run/Sleep modes, or temperature sensor enable in Low-power run/Low-power sleep modes. 2. Specified by design. Not tested in production. 

Table 23. Embedded reset and power control block characteristics (continued) Symbol Parameter Conditions (1) Min Typ Max Unit 

Table 24. Embedded internal voltage reference Symbol Parameter Conditions Min Typ Max Unit 

VREFINT Internal reference voltage -40°C < TJ < 130°C 1.182 1.212 1.232 VtS_vrefint (1) ADC sampling time when reading the internal reference voltage - 4(2) - - μs tstart_vrefint Start time of reference voltage buffer when ADC is enable - - 8 12 (2) μs DS12232 Rev 5 59/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 15. VREFINT vs. temperature 5.3.5 Supply current characteristics 

The current consumption is a function of several parameters and factors such as the operating voltage, ambient temperature, I/O pin loading, device software configuration, operating frequencies, I/O pin switching rate, program location in memory and executed binary code. The current consumption is measured as described in Figure 14: Current consumption measurement scheme .IDD(VREFINTBUF) VREFINT buffer consumption from VDD when converted by ADC - - 12.5 20 (2) μA 

∆VREFINT Internal reference voltage spread over the temperature range VDD = 3 V - 5 7.5 (2) mV TCoeff_vrefint Temperature coefficient - - 30 50 (2) ppm/°C ACoeff Long term stability 1000 hours, T = 25 °C - 300 1000 (2) ppm VDDCoeff Voltage coefficient 3.0 V < V DD < 3.6 V - 250 1200 (2) ppm/V VREFINT_DIV1 1/4 reference voltage -24 25 26 %VREFINT VREFINT_DIV2 1/2 reference voltage 49 50 51 VREFINT_DIV3 3/4 reference voltage 74 75 76 1. The shortest sampling time can be determined in the application by multiple iterations. 2. Specified by design. Not tested in production. 

Table 24. Embedded internal voltage reference (continued) Symbol Parameter Conditions Min Typ Max Unit         

> MSv40169V2 1.185 1.19 1.195 1.2 1.205 1.21 1.215 1.22 1.225 1.23 1.235 -40 -20 020 40 60 80 100 120

V°C Mean Min Max Electrical characteristics STM32G071x8/xB 

60/143 DS12232 Rev 5 

Typical and maximum current consumption 

The MCU is placed under the following conditions: 

• All I/O pins are in analog input mode 

• All peripherals are disabled except when explicitly mentioned 

• The flash memory access time is adjusted with the minimum wait states number, depending on the f HCLK frequency (refer to the table “Number of wait states according to CPU clock (HCLK) frequency” available in the RM0444 reference manual). 

• When the peripherals are enabled f PCLK = f HCLK 

• For flash memory and shared peripherals f PCLK = f HCLK = f HCLKS Unless otherwise stated, values given in Table 25 through Table 33 are derived from tests performed under ambient temperature and supply voltage conditions summarized in 

Table 21: General operating conditions .

Table 25. Current consumption in Run and Low-power run modes at different die temperatures Symbol Parameter Conditions Typ Max (1) Unit General fHCLK Fetch from (2) 25 °C 85 °C 125 °C 25 °C 85 °C 130 °C 

IDD(Run) Supply current in Run mode Range 1; 

PLL enabled; 

fHCLK = f HSE_bypass (≤16 MHz), 

fHCLK = f PLLRCLK (>16 MHz); 

> (3)

64 MHz Flash memory 6.3 6.4 6.8 6.7 7.0 7.7 mA 56 MHz 5.5 5.7 5.9 5.9 6.3 6.8 48 MHz 5.0 5.1 5.4 5.2 5.7 6.3 32 MHz 3.5 3.6 3.8 4.0 4.3 4.7 24 MHz 2.8 2.9 3.1 3.1 3.6 4.0 16 MHz 1.8 1.9 2.1 2.1 2.5 3.0 64 MHz SRAM 6.0 6.2 6.4 6.3 6.6 7.0 56 MHz 5.3 5.5 5.7 5.6 5.8 6.2 48 MHz 4.7 4.8 5.0 5.0 5.2 5.6 32 MHz 3.3 3.4 3.5 3.5 3.8 4.1 24 MHz 2.6 2.7 2.9 2.8 3.1 3.4 16 MHz 1.7 1.7 1.9 1.9 2.1 2.7 Range 2; 

PLL enabled; 

fHCLK = f HSE_bypass (≤16 MHz), 

fHCLK = fPLLRCLK (>16 MHz); 

> (3)

16 MHz Flash memory 1.4 1.5 1.7 1.7 2.0 2.6 8 MHz 0.8 0.9 1.0 1.2 1.3 1.8 2 MHz 0.3 0.3 0.5 0.5 0.8 1.4 16 MHz SRAM 1.4 1.4 1.6 1.6 1.8 2.2 8 MHz 0.7 0.8 1.0 1.1 1.2 1.6 4 MHz 0.4 0.5 0.6 0.7 0.9 1.5 2 MHz 0.3 0.3 0.5 0.5 0.8 1.2 DS12232 Rev 5 61/143 

STM32G071x8/xB Electrical characteristics 

> 110

IDD(LPRun) Supply current in Low-power run mode PLL disabled; 

fHCLK = fHSE bypass (> 32 kHz), 

fHCLK = fLSE bypass (= 32 kHz); 

> (3)

2 MHz Flash memory 220 255 420 530 795 1255 μA 1 MHz 105 155 320 505 770 1200 500 kHz 67 105 265 465 700 1110 125 kHz 26 66 230 450 520 1045 32 kHz 17 56 220 375 475 1035 2 MHz SRAM 199 231 380 485 700 1220 1 MHz 95 140 290 430 660 1140 500 kHz 61 95 240 365 625 1100 125 kHz 24 59 225 335 440 970 32 kHz 15 55 220 325 355 940 1. Based on characterization results, not tested in production. 2. Prefetch and cache enabled when fetching from flash memory. Code compiled with high optimization for space in SRAM. 3. VDD = 3.0 V for values in Typ columns and 3.6 V for values in Max columns, all peripherals disabled. 

Table 25. Current consumption in Run and Low-power run modes at different die temperatures (continued) Symbol Parameter Conditions Typ Max (1) Unit General fHCLK Fetch from (2) 25 °C 85 °C 125 °C 25 °C 85 °C 130 °C Electrical characteristics STM32G071x8/xB 

62/143 DS12232 Rev 5 

Table 26. Typical current consumption in Run and Low-power run modes, depending on code executed Symbol Parameter Conditions Typ Unit Typ Unit General Code Fetch from (1) 25 °C 25 °C 

IDD(Run) Supply current in Run mode Range 1; 

fHCLK = f PLLRCLK =64 MHz; 

> (2)

Reduced code (3) Flash memory 6.4 mA 100 

μA/MHz Coremark 6.2 97 Dhrystone 2.1 5.9 92 Fibonacci 4.6 71 While(1) loop 4.6 71 Reduced code (3) SRAM 6.2 96 Coremark 6.2 97 Dhrystone 2.1 6.0 93 Fibonacci 6.2 96 While(1) loop 4.8 75 Range 2; 

fHCLK = fHSI16 = 16 MHz, 

PLL disabled, 

> (2)

Reduced code (3) Flash memory 1.5 94 Coremark 1.5 94 Dhrystone 2.1 1.5 91 Fibonacci 1.1 69 While(1) loop 1.1 69 Reduced code (3) SRAM 1.5 91 Coremark 1.4 88 Dhrystone 2.1 1.4 84 Fibonacci 1.5 91 While(1) loop 1.1 69 IDD(LPRun) Supply current in Low-power run mode fHCLK = fHSI16/8 = 2 MHz; 

PLL disabled, 

> (2)

Reduced code (3) Flash memory 380 uA 190 uA/MHz Coremark 395 198 Dhrystone 2.1 405 203 Fibonacci 385 193 While(1) loop 400 200 Reduced code (3) SRAM 250 125 Coremark 245 123 Dhrystone 2.1 240 120 Fibonacci 250 125 While(1) loop 230 115 1. Prefetch and cache enabled when fetching from flash memory. Code compiled with high optimization for space in SRAM. 2. VDD = 3.3 V, all peripherals disabled, cache enabled, prefetch disabled for execution in flash memory and enabled in SRAM DS12232 Rev 5 63/143 

STM32G071x8/xB Electrical characteristics   

> 110
> 3. Reduced code used for characterization results provided in Table 25 .

Table 27. Current consumption in Sleep and Low-power sleep modes Symbol Parameter Conditions Typ Max (1) Unit General Voltage scaling fHCLK 25 °C 85 °C 125 °C 25 °C 85 °C 130 °C 

IDD(Sleep) Supply current in Sleep mode Flash memory enabled; 

fHCLK = f HSE bypass (≤16 MHz; PLL disabled), 

fHCLK = f PLLRCLK (>16 MHz; PLL enabled); 

All peripherals disabled Range 1 64 MHz 1.8 1.9 2.1 1.8 2.1 2.9 mA 56 MHz 1.6 1.7 1.9 1.7 1.9 2.8 48 MHz 1.4 1.5 1.7 1.6 1.7 2.7 32 MHz 1.0 1.1 1.3 1.2 1.3 2.3 24 MHz 0.8 0.9 1.1 1.0 1.1 1.9 16 MHz 0.5 0.6 0.8 0.6 0.7 1.7 Range 2 16 MHz 0.4 0.5 0.7 0.5 0.6 1.4 8 MHz 0.3 0.3 0.5 0.3 0.5 1.2 2 MHz 0.1 0.2 0.4 0.2 0.4 1.1 IDD(LPSleep) Supply current in Low-power sleep mode Flash memory disabled; 

PLL disabled; 

fHCLK = f HSE bypass (> 32 kHz), 

fHCLK = f LSE bypass (= 32 kHz); 

All peripherals disabled 2 MHz 60 99 265 150 360 1110 μA 1 MHz 33 75 240 130 330 1010 500 kHz 25 64 230 125 250 870 125 kHz 16 55 220 110 235 715 32 kHz 14 53 215 110 225 645 1. Based on characterization results, not tested in production. 

Table 28. Current consumption in Stop 0 mode Symbol Parameter Conditions Typ Max (1) Unit HSI kernel VDD 25°C 85°C 125°C 25°C 85°C 130°C 

IDD(Stop 0) Supply current in Stop 0 mode Enabled 1.8 V 275 305 430 330 425 750 μA 2.4 V 280 310 435 330 450 850 3 V 280 315 435 350 490 950 3.6 V 285 315 440 375 500 1020 Disabled 1.8 V 95 140 270 120 180 490 2.4 V 100 145 275 125 220 610 3 V 100 145 280 125 240 720 3.6 V 105 150 285 130 250 840 1. Based on characterization results, not tested in production. Electrical characteristics STM32G071x8/xB 

64/143 DS12232 Rev 5 

Table 29. Current consumption in Stop 1 mode Symbol Parameter Conditions Typ Max (1) Unit Flash memory RTC (2) VDD 25°C 85°C 125°C 25°C 85°C 130°C 

IDD(Stop 1) Supply current in Stop 1 mode Not powered Disabled 1.8 V 3.2 32 150 8 100 480 μA 2.4 V 3.3 32 150 10 120 535 3 V 3.4 33 155 15 135 620 3.6 V 3.8 33 155 18 140 705 Enabled 1.8 V 3.4 32 150 9 100 480 2.4 V 3.7 32 155 11 120 540 3 V 4.0 33 155 16 140 630 3.6 V 4.4 34 160 20 145 720 Powered Disabled 1.8 V 6.9 36 155 12 100 575 2.4 V 7.3 36 160 14 110 600 3 V 7.3 37 160 18 120 645 3.6 V 7.8 38 160 23 135 665 1. Based on characterization results, not tested in production. 2. Clocked by LSI 

Table 30. Current consumption in Standby mode Symbol Parameter Conditions Typ Max (1) Unit General VDD 25°C 85°C 125°C 25°C 85°C 130°C 

IDD(Standby) Supply current in Standby mode (2) RTC disabled 1.8 V 0.07 1.7 6.7 0.7 9 34 μA 2.4 V 0.13 2.1 8.1 0.8 12 38 3.0 V 0.20 2.5 10.0 0.9 14 46 3.6 V 0.34 3.0 12.0 1.0 16 55 RTC enabled, clocked by LSI; 1.8 V 0.35 2.0 7.0 0.8 10 35 2.4 V 0.49 2.4 8.4 1.0 12 40 3.0 V 0.66 2.9 10.5 1.3 15 47 3.6 V 0.90 3.5 12.5 2.2 18 56 IWDG enabled, clocked by LSI 1.8 V 0.26 1.9 6.8 0.8 10 34 2.4 V 0.37 2.3 8.3 1.0 12 39 3.0 V 0.49 2.7 10.3 1.4 15 45 3.6 V 0.69 3.3 12.3 2.1 18 52 ENB_ULP = 0 1.8 V 0.70 1.6 6.6 - - -2.4 V 0.89 2.0 8.0 - - -3.0 V 1.10 2.4 9.8 - - -3.6 V 1.30 2.9 11.8 - - -DS12232 Rev 5 65/143 

STM32G071x8/xB Electrical characteristics 

> 110

∆IDD(SRAM) Extra supply current to retain SRAM content (3) SRAM retention enabled 1.8 V 0.49 3.0 14.8 0.6 16 58 μA 2.4 V 0.57 3.1 14.9 1.1 17 63 3.0 V 0.67 3.2 15.0 1.5 17 67 3.6 V 0.77 3.3 15.0 1.9 18 71 1. Based on characterization results, not tested in production. 2. Without SRAM retention and with ULPEN bit set 3. To be added to I DD(Standby) as appropriate 

Table 30. Current consumption in Standby mode (continued) Symbol Parameter Conditions Typ Max (1) Unit General VDD 25°C 85°C 125°C 25°C 85°C 130°C 

Table 31. Current consumption in Shutdown mode Symbol Parameter Conditions Typ Max (1) Unit RTC VDD 25 °C 85 °C 125 °C 25 °C 85 °C 130 °C 

IDD(Shutdown) Supply current in Shutdown mode Disabled 1.8 V 17 515 4500 250 3000 32600 nA 2.4 V 23 600 5150 450 3500 33600 3.0 V 33 730 6450 1075 4250 37400 3.6 V 53 940 7700 1250 5300 43600 Enabled, clocked by LSE bypass at 32.768 kHz 1.8 V 205 710 4700 900 4500 27300 2.4 V 300 890 5500 1550 5500 34800 3.0 V 420 1150 6800 2475 6000 40900 3.6 V 565 1450 8100 3250 7000 48500 1. Based on characterization results, not tested in production. 

Table 32. Current consumption in VBAT mode Symbol Parameter Conditions Typ Unit RTC VDD 25°C 85°C 125°C 

IDD(VBAT) Supply current in VBAT mode Enabled, clocked by LSE bypass at 32.768 kHz 1.8 V 165 170 620 nA 2.4 V 260 355 970 3.0 V 365 475 1200 3.6 V 505 655 2070 Enabled, clocked by LSE crystal at 32.768 kHz 1.8 V 290 390 960 2.4 V 370 480 1150 3.0 V 470 600 1650 3.6 V 600 815 2250 Disabled 1.8 V 1 80 660 2.4 V 2 90 750 3.0 V 2 105 1200 3.6 V 6 200 1700 Electrical characteristics STM32G071x8/xB  

> 66/143 DS12232 Rev 5

I/O system current consumption 

The current consumption of the I/O system has two components: static and dynamic. 

I/O static current consumption 

All the I/Os used with internal or external pull-up or pull-down resistor generate current consumption when the pin is externally or internally tied low or high, respectively. The value of this current consumption can be simply computed by using the pull-up/pull-down resistor values. For internal pull-up/pull-down resistors, the indicative values are given in Table 51: I/O static characteristics . Any other external load must also be considered to estimate the current consumption. Additional I/O current consumption is due to I/Os configured as inputs if an intermediate voltage level is externally applied. This current consumption is caused by the input Schmitt trigger circuits used to discriminate the input value. Unless this specific configuration is required by the application, this supply current consumption can be avoided by configuring these I/Os in analog mode. This is notably the case of ADC input pins which should be configured as analog inputs. 

Caution: Any floating input pin can also settle to an intermediate voltage level or switch inadvertently, as a result of external electromagnetic noise. To avoid current consumption related to floating pins, they must either be configured in analog mode, or forced internally to a definite digital value. This can be done either by using pull-up/down resistors or by configuring the pins in output mode. 

I/O dynamic current consumption 

In addition to the internal peripheral current consumption measured previously (see 

Table 33: Current consumption of peripherals ), the I/Os used by an application also contribute to the current consumption. When an I/O pin switches, it uses the current from the I/O supply voltage to supply the I/O pin circuitry and to charge/discharge the capacitive load (internal and external) connected to the pin: where ISW is the current sunk by a switching I/O to charge/discharge the capacitive load VDDIO1 is the I/O supply voltage fSW is the I/O switching frequency C is the total capacitance seen by the I/O pin: C = C INT + C EXT + C SCS is the PCB board capacitance including the pad pin. The test pin is configured in push-pull output mode and is toggled by software at a fixed frequency. ISW VDDIO1 fSW C××=DS12232 Rev 5 67/143 

STM32G071x8/xB Electrical characteristics 

> 110

On-chip peripheral current consumption 

The current consumption of the on-chip peripherals is given in the following table. The MCU is placed under the following conditions: 

• All I/O pins are in Analog mode 

• The given value is calculated by measuring the difference of the current consumptions: – when the peripheral is clocked on – when the peripheral is clocked off 

• Ambient operating temperature and supply voltage conditions summarized in Table 18: Voltage characteristics 

• The power consumption of the digital part of the on-chip peripherals is given in the following table. The power consumption of the analog part of the peripherals (where applicable) is indicated in each related section of the datasheet. 

Table 33. Current consumption of peripherals Peripheral Bus Consumption in μA/MHz Range 1 Range 2 Low-power run and sleep                                                                                                 

> IOPORT Bus IOPORT 1.0 0.7 0.5 GPIOA IOPORT 3.4 2.8 3.0 GPIOB IOPORT 3.1 2.6 2.5 GPIOC IOPORT 2.9 2.5 3.0 GPIOD IOPORT 1.8 1.5 1.5 GPIOF IOPORT 0.7 0.6 1.0 Bus matrix AHB 3.2 2.2 2.8 All AHB Peripherals AHB 15.0 12.5 14.0 DMA1/DMAMUX AHB 4.7 3.8 4.5 CRC AHB 0.5 0.4 0.5 FLASH AHB 4.1 3.5 4.0 All APB peripherals APB 46.5 47.5 48.0 AHB to APB bridge (1) APB 0.2 0.2 0.1 PWR APB 0.4 0.3 0.5 SYSCFG/VREFBUF/COMP APB 0.4 0.4 0.3 WWDG APB 0.4 0.3 0.5 TIM1 APB 7.3 6.1 6.5 TIM2 APB 4.7 3.8 5.0 TIM3 APB 3.6 3.0 2.5 TIM6 APB 0.7 0.6 0.5 TIM7 APB 0.7 0.7 1.0 TIM14 APB 1.5 1.2 1.5 TIM15 APB 4.0 3.3 3.0 TIM16 APB 2.3 2.0 2.0

Electrical characteristics STM32G071x8/xB 

68/143 DS12232 Rev 5 

## 5.3.6 Wakeup time from low-power modes and voltage scaling 

## transition times 

The wakeup times given in Table 34 are the latency between the event and the execution of the first user instruction. TIM17 APB 0.7 0.7 0.5 LPTIM1 APB 3.2 2.7 3.0 LPTIM2 APB 3.1 2.5 3.0 I2C1 APB 3.8 3.1 3.5 I2C2 APB 0.7 0.6 1.0 SPI2 APB 1.5 1.2 1.0 USART1 APB 7.2 6.0 6.5 USART2 APB 7.2 6.0 6.0 USART3 APB 2.0 1.7 2.0 USART4 APB 2.0 1.7 2.0 LPUART1 APB 4.3 3.5 4.0 CEC APB 0.4 0.3 0.5 UCPD1 APB 4.0 7.7 NA (2) UCPD2 APB 4.0 7.7 NA (2) ADC APB 2.0 1.7 2.0 DAC APB 2.2 1.8 2.0 1. The AHB to APB Bridge is automatically active when at least one peripheral is ON on the APB. 2. UCPDx are always clocked by HSI16. 

Table 33. Current consumption of peripherals (continued) Peripheral Bus Consumption in μA/MHz Range 1 Range 2 Low-power run and sleep 

Table 34. Low-power mode wakeup times (1) Symbol Parameter Conditions Typ Max Unit 

tWUSLEEP Wakeup time from Sleep to Run mode - 11 11 CPU cycles tWULPSLEEP Wakeup time from Low-power sleep mode Transiting to Low-power-run-mode execution in flash memory not powered in Low-power sleep mode; HCLK = HSI16 / 8 = 2 MHz 11 14 CPU cycles DS12232 Rev 5 69/143 

STM32G071x8/xB Electrical characteristics 

> 110

tWUSTOP0 Wakeup time from Stop 0 Transiting to Run-mode execution in flash memory not powered in Stop 0 mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 or Range 2 5.6 6μs Transiting to Run-mode execution in SRAM or in flash memory powered in Stop 0 mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 or Range 2 2 2.4 tWUSTOP1 Wakeup time from Stop 1 Transiting to Run-mode execution in flash memory not powered in Stop 1 mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 or Range 2 9.0 11.2 μs Transiting to Run-mode execution in SRAM or in flash memory powered in Stop 1 mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 or Range 2 5 7.5 Transiting to Low-power-run-mode execution in flash memory not powered in Stop 1 mode; HCLK = HSI16/8 = 2 MHz; Regulator in low-power mode (LPR = 1 in PWR_CR1) 22 25.3 Transiting to Low-power-run-mode execution in SRAM or in flash memory powered in Stop 1 mode; HCLK = HSI16 / 8 = 2 MHz; Regulator in low-power mode (LPR = 1 in PWR_CR1) 18 23.5 tWUSTBY Wakeup time from Standby mode Transiting to Run mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 14.5 30 μs tWUSHDN Wakeup time from Shutdown mode Transiting to Run mode; HCLK = HSI16 = 16 MHz; Regulator in Range 1 258 340 μs tWULPRUN Wakeup time from Low-power run mode (2) Transiting to Run mode; HSISYS = HSI16/8 = 2 MHz 5 7 μs 1. Based on characterization results, not tested in production. 2. Time until REGLPF flag is cleared in PWR_SR2. 

Table 34. Low-power mode wakeup times (1) (continued) Symbol Parameter Conditions Typ Max Unit 

Table 35. Regulator mode transition times (1) Symbol Parameter Conditions Typ Max Unit 

tVOST Transition times between regulator Range 1 and Range 2 (2) HSISYS = HSI16 20 40 μs 1. Based on characterization results, not tested in production. 2. Time until VOSF flag is cleared in PWR_SR2. Electrical characteristics STM32G071x8/xB 

70/143 DS12232 Rev 5 

## 5.3.7 External clock source characteristics High-speed external user clock generated from an external source 

In bypass mode the HSE oscillator is switched off and the input pin is a standard GPIO. The external clock signal has to respect the I/O characteristics in Section 5.3.14 . See 

Figure 16 for recommended clock input waveform. 

Figure 16. High-speed external clock source AC timing diagram Table 36. Wakeup time using LPUART (1) Symbol Parameter Conditions Typ Max Unit 

tWULPUART Wakeup time needed to calculate the maximum LPUART baud rate allowing to wakeup up from Stop mode when LPUART clock source is HSI16 Stop mode 0 - 1.7 μs Stop mode 1 - 8.5 1. Specified by design. Not tested in production. 

Table 37. High-speed external user clock characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fHSE_ext User external clock source frequency Voltage scaling Range 1 - 8 48 MHz Voltage scaling Range 2 - 8 26 VHSEH OSC_IN input pin high level voltage - 0.7 VDDIO1 - VDDIO1 VVHSEL OSC_IN input pin low level voltage - VSS - 0.3 V DDIO1 Vtw(HSEH) tw(HSEL) OSC_IN high or low time Voltage scaling Range 1 7 - -ns Voltage scaling Range 2 18 - -1. Specified by design. Not tested in production. 

> MS19214V2 VHSEH tf(HSE) 90% 10% THSE ttr(HSE) VHSEL tw(HSEH) tw(HSEL)

DS12232 Rev 5 71/143 

STM32G071x8/xB Electrical characteristics 

> 110

Low-speed external user clock generated from an external source 

In bypass mode the LSE oscillator is switched off and the input pin is a standard GPIO. The external clock signal has to respect the I/O characteristics in Section 5.3.14 . See 

Figure 17 for recommended clock input waveform. 

Figure 17. Low-speed external clock source AC timing diagram High-speed external clock generated from a crystal/ceramic resonator 

The high-speed external (HSE) clock can be supplied with a 4 to 48 MHz crystal/ceramic resonator oscillator. All the information given in this paragraph are based on design simulation results obtained with typical external components specified in Table 39 . In the application, the resonator and the load capacitors have to be placed as close as possible to the oscillator pins in order to minimize output distortion and startup stabilization time. Refer to the crystal resonator manufacturer for more details on the resonator characteristics (frequency, package, accuracy). 

Table 38. Low-speed external user clock characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fLSE_ext User external clock source frequency - - 32.768 1000 kHz VLSEH OSC32_IN input pin high level voltage - 0.7 V DDIO1 - VDDIO1 VVLSEL OSC32_IN input pin low level voltage - VSS - 0.3 V DDIO1 Vtw(LSEH) tw(LSEL) OSC32_IN high or low time - 250 - - ns 1. Specified by design. Not tested in production. 

> MS19215V2 VLSEH tf(LSE) 90% 10% TLSE ttr(LSE) VLSEL tw(LSEH) tw(LSEL)

Table 39. HSE oscillator characteristics (1) Symbol Parameter Conditions (2) Min Typ Max Unit 

fOSC_IN Oscillator frequency - 4 8 48 MHz RF Feedback resistor - - 200 - kΩElectrical characteristics STM32G071x8/xB 

72/143 DS12232 Rev 5 

For CL1 and CL2, it is recommended to use high-quality external ceramic capacitors in the 5 pF to 20 pF range (typ.), designed for high-frequency applications, and selected to match the requirements of the crystal or resonator (see Figure 18 ). CL1 and CL2 are usually the same size. The crystal manufacturer typically specifies a load capacitance which is the series combination of CL1 and CL2. PCB and MCU pin capacitance must be included (10 pF can be used as a rough estimate of the combined pin and board capacitance) when sizing CL1 and CL2. 

Note: For information on selecting the crystal, refer to the application note AN2867 “Oscillator design guide for ST microcontrollers” available from the ST website www.st.com. 

IDD(HSE) HSE current consumption During startup (3) - - 5.5 mA VDD = 3 V, 

Rm = 30 Ω,

CL = 10 pF@8 MHz - 0.44 -VDD = 3 V, 

Rm = 45 Ω,

CL = 10 pF@8 MHz - 0.45 -VDD = 3 V, 

Rm = 30 Ω,

CL = 5 pF@48 MHz - 0.68 -VDD = 3 V, 

Rm = 30 Ω,

CL = 10 pF@48 MHz - 0.94 -VDD = 3 V, 

Rm = 30 Ω,

CL = 20 pF@48 MHz - 1.77 -Gm Maximum critical crystal transconductance Startup - - 1.5 mA/V tSU(HSE) (4) Startup time VDD is stabilized - 2 - ms 1. Specified by design. Not tested in production. 2. Resonator characteristics given by the crystal/ceramic resonator manufacturer. 3. This consumption level occurs during the first 2/3 of the tSU(HSE) startup time 4. tSU(HSE) is the startup time measured from the moment it is enabled (by software) to a stabilized 8 MHz oscillation is reached. This value is measured for a standard crystal resonator and it can vary significantly with the crystal manufacturer 

Table 39. HSE oscillator characteristics (1) (continued) Symbol Parameter Conditions (2) Min Typ Max Unit DS12232 Rev 5 73/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 18. Typical application with an 8 MHz crystal  

> 1. REXT value depends on the crystal characteristics.

Low-speed external clock generated from a crystal resonator 

The low-speed external (LSE) clock can be supplied with a 32.768 kHz crystal resonator oscillator. All the information given in this paragraph are based on design simulation results obtained with typical external components specified in Table 40 . In the application, the resonator and the load capacitors have to be placed as close as possible to the oscillator pins in order to minimize output distortion and startup stabilization time. Refer to the crystal resonator manufacturer for more details on the resonator characteristics (frequency, package, accuracy). 

> MS19876V1 (1) OSC_IN OSC_OUT RF Bias controlled gain fHSE REXT 8 MHz resonator Resonator with integrated capacitors CL1 CL2

Table 40. LSE oscillator characteristics (fLSE = 32.768 kHz) (1) Symbol Parameter Conditions (2) Min Typ Max Unit 

IDD(LSE) LSE current consumption LSEDRV[1:0] = 00 

Low drive capability - 250 -nA LSEDRV[1:0] = 01 

Medium low drive capability - 315 -LSEDRV[1:0] = 10 

Medium high drive capability - 500 -LSEDRV[1:0] = 11 

High drive capability - 630 -Gm critmax Maximum critical crystal gm LSEDRV[1:0] = 00 

Low drive capability - - 0.5 μA/V LSEDRV[1:0] = 01 

Medium low drive capability - - 0.75 LSEDRV[1:0] = 10 

Medium high drive capability - - 1.7 LSEDRV[1:0] = 11 

High drive capability - - 2.7 tSU(LSE) (3) Startup time VDD is stabilized - 2 - s1. Specified by design. Not tested in production. 2. Refer to the note and caution paragraphs below the table, and to the application note AN2867 “Oscillator design guide for ST microcontrollers”. Electrical characteristics STM32G071x8/xB 

74/143 DS12232 Rev 5 

Note: For information on selecting the crystal, refer to the application note AN2867 “Oscillator design guide for ST microcontrollers” available from the ST website www.st.com. 

Figure 19. Typical application with a 32.768 kHz crystal 

Note: An external resistor is not required between OSC32_IN and OSC32_OUT and it is forbidden to add one. 

## 5.3.8 Internal clock source characteristics 

The parameters given in Table 41 are derived from tests performed under ambient temperature and supply voltage conditions summarized in Table 21: General operating conditions . The provided curves are characterization results, not tested in production. 

High-speed internal (HSI16) RC oscillator  

> 3. tSU(LSE) is the startup time measured from the moment it is enabled (by software) to a stabilized 32.768 kHz oscillation is reached. This value is measured for a standard crystal and it can vary significantly with the crystal manufacturer
> MS30253V2 OSC32_IN OSC32_OUT Drive programmable amplifier fLSE 32.768 kHz resonator Resonator with integrated capacitors CL1 CL2

Table 41. HSI16 oscillator characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fHSI16 HSI16 Frequency VDD=3.0 V, TA=30 °C 15.88 - 16.08 MHz 

∆Temp(HSI16) HSI16 oscillator frequency drift over temperature TA= 0 to 85 °C -1 - 1 %TA= -40 to 125 °C -2 - 1.5 %

∆VDD(HSI16) HSI16 oscillator frequency drift over VDD VDD=1.62 V to 3.6 V -0.1 - 0.05 %TRIM HSI16 frequency user trimming step From code 127 to 128 -8 -6 -4 %From code 63 to 64 From code 191 to 192 -5.8 -3.8 -1.8 For all other code increments 0.2 0.3 0.4 DHSI16 (2) Duty Cycle - 45 - 55 %tsu(HSI16) (2) HSI16 oscillator start-up time - - 0.8 1.2 μsDS12232 Rev 5 75/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 20. HSI16 frequency vs. temperature Low-speed internal (LSI) RC oscillator 

tstab(HSI16) (2) HSI16 oscillator stabilization time - - 3 5 μsIDD(HSI16) (2) HSI16 oscillator power consumption - - 155 190 μA1. Based on characterization results, not tested in production. 2. Specified by design. Not tested in production. 

Table 41. HSI16 oscillator characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit           

> MSv39299V2 15.6 15.7 15.8 15.9 16 16.1 16.2 16.3 16.4 -40 -20 020 40 60 80 100 120 MHz °C Mean min max +2 % +1.5 % +1 % -1 % -1.5 % -2 %

Table 42. LSI oscillator characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fLSI LSI frequency VDD = 3.0 V, TA = 30 °C 31.04 - 32.96 kHz VDD = 1.62 V to 3.6 V, T A = -40 to 125 °C 29.5 - 34 tSU(LSI) (2) LSI oscillator start-up time - - 80 130 μstSTAB(LSI) (2) LSI oscillator stabilization time 5% of final frequency - 125 180 μsIDD(LSI) (2) LSI oscillator power consumption - - 110 180 nA 1. Based on characterization results, not tested in production. 2. Specified by design. Not tested in production. Electrical characteristics STM32G071x8/xB 

76/143 DS12232 Rev 5 

## 5.3.9 PLL characteristics 

The parameters given in Table 43 are derived from tests performed under temperature and VDD supply voltage conditions summarized in Table 21: General operating conditions .

## 5.3.10 Flash memory characteristics 

Table 43. PLL characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fPLL_IN PLL input clock frequency (2) - 2.66 - 16 MHz DPLL_IN PLL input clock duty cycle - 45 - 55 %fPLL_P_OUT PLL multiplier output clock P Voltage scaling Range 1 3.09 - 122 MHz Voltage scaling Range 2 3.09 - 40 fPLL_Q_OUT PLL multiplier output clock Q Voltage scaling Range 1 12 - 128 MHz Voltage scaling Range 2 12 - 33 fPLL_R_OUT PLL multiplier output clock R Voltage scaling Range 1 12 - 64 MHz Voltage scaling Range 2 12 - 16 fVCO_OUT PLL VCO output Voltage scaling Range 1 96 - 344 MHz Voltage scaling Range 2 96 - 128 tLOCK PLL lock time - - 15 40 μsJitter RMS cycle-to-cycle jitter System clock 56 MHz - 50 - ±ps RMS period jitter - 40 -IDD(PLL) PLL power consumption 

on V DD (1) VCO freq = 96 MHz - 200 260 

μAVCO freq = 192 MHz - 300 380 VCO freq = 344 MHz - 520 650 1. Specified by design. Not tested in production. 2. Make sure to use the appropriate division factor M to obtain the specified PLL input clock values. 

Table 44. Flash memory characteristics (1) Symbol Parameter Conditions Typ Max Unit 

tprog 64-bit programming time - 85 125 μs tprog_row Row (32 double word) programming time Normal programming 2.7 4.6 ms Fast programming 1.7 2.8 tprog_page Page (2 Kbyte) programming time Normal programming 21.8 36.6 ms Fast programming 13.7 22.4 tERASE Page (2 Kbyte) erase time - 22.0 40.0 ms tprog_bank Bank (128 Kbyte (2) ) programming time Normal programming 1.4 2.4 sFast programming 0.9 1.4 tME Mass erase time - 22.1 40.1 ms DS12232 Rev 5 77/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.11 EMC characteristics 

Susceptibility tests are performed on a sample basis during device characterization. 

Functional EMS (electromagnetic susceptibility) 

While a simple application is executed on the device (toggling 2 LEDs through I/O ports). the device is stressed by two electromagnetic events until a failure occurs. The failure is indicated by the LEDs: 

• Electrostatic discharge (ESD) (positive and negative) is applied to all device pins until a functional disturbance occurs. This test is compliant with the IEC 61000-4-2 standard. 

• FTB : A Burst of Fast Transient voltage (positive and negative) is applied to V DD and VSS through a 100 pF capacitor, until a functional disturbance occurs. This test is compliant with the IEC 61000-4-4 standard. A device reset allows normal operations to be resumed. The test results are given in Table 46 . They are based on the EMS levels and classes defined in application note AN1709. IDD(FlashA) Average consumption from VDD Programming 3 -mA Page erase 3 -Mass erase 3 -IDD(FlashP) Maximum current (peak) Programming, 2 μs peak duration 7 - mA Erase, 41 μs peak duration 7 -1. Specified by design. Not tested in production. 2. Values provided also apply to devices with less flash memory than one 128 Kbyte bank 

Table 44. Flash memory characteristics (1) (continued) Symbol Parameter Conditions Typ Max Unit 

Table 45. Flash memory endurance and data retention Symbol Parameter Conditions Min (1) Unit 

NEND Endurance TA = -40 to +105 °C 10 kcycles tRET Data retention 1 kcycle (2) at T A = 85 °C 30 Years 1 kcycle (2) at TA = 105 °C 15 1 kcycle (2) at T A = 125 °C 710 kcycles (2) at TA = 55 °C 30 10 kcycles (2) at TA = 85 °C 15 10 kcycles (2) at T A = 105 °C 10 1. Evaluated by characterization. Not tested in production. 2. Cycling performed over the whole temperature range. Electrical characteristics STM32G071x8/xB 

78/143 DS12232 Rev 5 

Designing hardened software to avoid noise problems 

EMC characterization and optimization are performed at component level with a typical application environment and simplified MCU software. It should be noted that good EMC performance is highly dependent on the user application and the software in particular. Therefore it is recommended that the user applies EMC software optimization and prequalification tests in relation with the EMC level requested for his application. 

Software recommendations 

The software flowchart must include the management of runaway conditions such as: 

• corrupted program counter 

• unexpected reset 

• critical data corruption (for example control registers) 

Prequalification trials 

Most of the common failures (unexpected reset and program counter corruption) can be reproduced by manually forcing a low state on the NRST pin or the Oscillator pins for 1 second. To complete these trials, ESD stress can be applied directly on the device, over the range of specification values. When unexpected behavior is detected, the software can be hardened to prevent unrecoverable errors occurring (see application note AN1015). 

Electromagnetic Interference (EMI) 

The electromagnetic field emitted by the device are monitored while a simple application is executed (toggling 2 LEDs through the I/O ports). This emission test is compliant with IEC 61967-2 standard which specifies the test board and the pin loading. 

Table 46. EMS characteristics Symbol Parameter Conditions Level/ Class 

VFESD Voltage limits to be applied on any I/O pin to induce a functional disturbance VDD = 3.3 V, T A = +25 °C, 

fHCLK = 64 MHz, LQFP64, 

conforming to IEC 61000-4-2 2B VEFTB Fast transient voltage burst limits to be applied through 100 pF on V DD and V SS pins to induce a functional disturbance VDD = 3.3 V, T A = +25 °C, 

fHCLK = 64 MHz, LQFP64, 

conforming to IEC 61000-4-4 5A 

Table 47. EMI characteristics Symbol Parameter Conditions Monitored frequency band Value Unit 

SEMI Peak (1) fHSE = 8 MHz 

fHCLK = 64 MHz 

VDD = 3.6 V, T A = 25 °C, 

LQFP64 package compliant with IEC 61967-2 0.1 MHz to 30 MHz 7dBμV 30 MHz to 130 MHz -1 130 MHz to 1 GHz 81 GHz to 2 GHz 7Level (2) 0.1 MHz to 2 GHz 2.5 -1. Refer to AN1709 “EMI radiated test” section. DS12232 Rev 5 79/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.12 Electrical sensitivity characteristics 

Based on three different tests (ESD, LU) using specific measurement methods, the device is stressed in order to determine its performance in terms of electrical sensitivity. 

Electrostatic discharge (ESD) 

Electrostatic discharges (a positive then a negative pulse separated by 1 second) are applied to the pins of each sample according to each pin combination. The sample size depends on the number of supply pins in the device (3 parts × (n+1) supply pins). This test conforms to the ANSI/JEDEC standard. 

Static latch-up 

Two complementary static tests are required on six parts to assess the latch-up performance: 

• A supply overvoltage is applied to each power supply pin. 

• A current is injected to each input, output and configurable I/O pin. These tests are compliant with EIA/JESD 78A IC latch-up standard. 

## 5.3.13 I/O current injection characteristics 

As a general rule, current injection to the I/O pins, due to external voltage below VSS or above VDDIO1 (for standard, 3.3 V-capable I/O pins) should be avoided during normal product operation. However, in order to give an indication of the robustness of the microcontroller in cases when abnormal injection accidentally happens, susceptibility tests are performed on a sample basis during device characterization. 

Functional susceptibility to I/O current injection 

While a simple application is executed on the device, the device is stressed by injecting current into the I/O pins programmed in floating input mode. While current is injected into the I/O pin, one at a time, the device is checked for functional failures. 2. Refer to AN1709 “EMI level classification” section 

Table 48. ESD absolute maximum ratings Symbol Ratings Conditions Class Maximum value (1) Unit         

> VESD(HBM) Electrostatic discharge voltage (human body model) TA = +25 °C, conforming to ANSI/ESDA/JEDEC JS-001 22000 VVESD(CDM) Electrostatic discharge voltage (charge device model) TA = +25 °C, conforming to ANSI/ESDA/JEDEC JS-002 C2a 500 V1. Based on characterization results, not tested in production.

Table 49. Electrical sensitivity Symbol Parameter Conditions Class    

> LU Static latch-up class TA = +125 °C conforming to JESD78 II Level A

Electrical characteristics STM32G071x8/xB 

80/143 DS12232 Rev 5 

The failure is indicated by an out-of-range parameter: ADC error above a certain limit (higher than 5 LSB TUE), induced leakage current on adjacent pins out of conventional limits (-5 μA/+0 μA range) or other functional failure (for example reset occurrence or oscillator frequency deviation). Negative induced leakage current is caused by negative injection and positive induced leakage current is caused by positive injection. 

Table 50. I/O current injection susceptibility (1) Symbol Description Functional susceptibility Unit Negative injection Positive injection 

IINJ Injected current on pin All except PA4, PA5, PA6, PB0, PB3, and PC0 -5 N/A mA PA4, PA5 -5 0 mA PA6, PB0, PB3, and PC0 0 N/A mA 1. Based on characterization results, not tested in production. DS12232 Rev 5 81/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.14 I/O port characteristics General input/output characteristics 

Unless otherwise specified, the parameters given in Table 51 are derived from tests performed under the conditions summarized in Table 21: General operating conditions . All I/Os are designed as CMOS- and TTL-compliant. 

Note: For information on GPIO configuration, refer to the application note AN4899 “STM32 GPIO configuration for hardware settings and low-power consumption” available from the ST website www.st.com. 

Table 51. I/O static characteristics Symbol Parameter Conditions Min Typ Max Unit 

VIL (1) I/O input low level voltage All except FT_c 1.62 V < V DDIO1 < 3.6 V - -0.3 x VDDIO1 (2) V0.39 x V DDIO1 - 0.06 (3) FT_c 2.7 V < V DDIO1 < 3.6 V - - 0.3 x V DDIO1 1.62 V < V DDIO1 < 2.7 V - - 0.25 x VDDIO1 VIH (1) I/O input high level voltage All except FT_c 1.62 V < V DDIO1 < 3.6 V 0.7 x VDDIO1 (2) - -V0.49 x V DDIO1 + 0.26 (3) - -FT_c 1.62 V < V DDIO1 < 3.6 V 0.7 x VDDIO1 - 5Vhys (3) I/O input hysteresis TT_xx, FT_xx, RST 1.62 V < V DDIO1 < 3.6 V - 200 - mV Ilkg Input leakage current (3) FT_c 0 < VIN ≤ VDDIO1 - - 2000 nA VDDIO1 < V IN ≤ 5 V - - 3000 (4) FT_d 0 < VIN ≤ VDDIO1 - - 4500 VDDIO1 < VIN ≤ 5.5 V - - 9000 (4) Other FT_xx 0 < V IN ≤ VDDIO1 - - ±70 VDDIO1 ≤ VIN ≤ VDDIO1 + 1 V - - 600 (4) VDDIO1 +1 V < VIN ≤ 5.5 V - - 150 (4) TT_a 0 < V IN ≤ VDDIO1 - - ±150 VDDIO1 < V IN ≤

VDDIO1 + 0.3 V - - 2000 (4) RPU Weak pull-up equivalent resistor (5) VIN = VSS 25 40 55 kΩ

RPD Weak pull-down equivalent resistor (5) VIN = V DDIO1 25 40 55 kΩ

CIO I/O pin capacitance - - 5 - pF Electrical characteristics STM32G071x8/xB 

82/143 DS12232 Rev 5 

All I/Os are CMOS- and TTL-compliant (no software configuration required). Their characteristics cover more than the strict CMOS-technology or TTL parameters, as shown in Figure 21 .

Figure 21. I/O input characteristics Output driving current 

The GPIOs (general purpose input/outputs) can sink or source up to ±8 mA, and up to ±15 mA with relaxed V OL /V OH .In the user application, the number of I/O pins which can drive current must be limited to respect the absolute maximum rating specified in Section 5.2 :

• The sum of the currents sourced by all the I/Os on V DDIO1, plus the maximum consumption of the MCU sourced on V DD, cannot exceed the absolute maximum rating IVDD (see Table 18: Voltage characteristics ). 

• The sum of the currents sunk by all the I/Os on V SS , plus the maximum consumption of the MCU sunk on V SS , cannot exceed the absolute maximum rating I VSS (see Table 18: Voltage characteristics ). 1. Refer to Figure 21: I/O input characteristics .2. Tested in production. 3. Specified by design. Not tested in production. 4. This value represents the pad leakage of the I/O itself. The total product pad leakage is provided by this formula: 

ITotal_Ileak_max = 10 μA + [number of I/Os where VIN is applied on the pad] ₓ Ilkg(Max). 5. Pull-up and pull-down resistors are designed with a true resistance in series with a switchable PMOS/NMOS. This PMOS/NMOS contribution to the series resistance is minimal (~10% order).           

> MSv47925V2 1.6 1.8 2.0 2.2 2.4 2.6 2.8 3.0 3.2 3.4 3.6 00.5 11.5 22.5 3

Mandatory logic level 1 zone Mandatory logic level 0 zone VIHmin = 0.7 VDDIO1 (CMOS standard requirement) VILmax = 0.3 VDDIO1 (CMOS standard requirement) Undefined input range VIHmin = 0.49 VDDIO1 + 0.26 VILmax = 0.39 VDDIO1 - 0.06 VIN (V) VDDIO1 (V) TTL standard requirement TTL standard requirement Device characteristics Test thresholds DS12232 Rev 5 83/143 

STM32G071x8/xB Electrical characteristics 

> 110

Output voltage levels 

Unless otherwise specified, the parameters given in the table below are derived from tests performed under the ambient temperature and supply voltage conditions summarized in 

Table 21: General operating conditions . All I/Os are CMOS- and TTL-compliant (FT OR TT unless otherwise specified). 

Output buffer timing characteristics 

The definition and values of input/output AC characteristics are given in Figure 22 and 

Table 53 , respectively. Unless otherwise specified, the parameters given are derived from tests performed under the ambient temperature and supply voltage conditions summarized in Table 21: General operating conditions .

Table 52. Output voltage characteristics (1)(2) Symbol Parameter Conditions Min Max Unit 

VOL Output low level voltage for an I/O pin CMOS port (3) 

|I IO | = 2 mA for FT_c I/Os 

= 8 mA for other I/Os 

VDDIO1 ≥ 2.7 V - 0.4 VVOH Output high level voltage for an I/O pin VDDIO1 - 0.4 - VVOL (4) Output low level voltage for an I/O pin TTL port (3) 

|I IO | = 2 mA for FT_c I/Os 

= 8 mA for other I/Os 

VDDIO1 ≥ 2.7 V - 0.4 VVOH (4) Output high level voltage for an I/O pin 2.4 - VVOL (4) Output low level voltage for an I/O pin All I/Os except FT_c 

|IIO| = 15 mA 

VDDIO1 ≥ 2.7 V - 1.3 VVOH (4) Output high level voltage for an I/O pin VDDIO1 - 1.3 - VVOL (4) Output low level voltage for an I/O pin |IIO| = 1 mA for FT_c I/Os 

= 3 mA for other I/Os 

VDDIO1 ≥ VDD (min) - 0.4 VVOH (4) Output high level voltage for an I/O pin VDDIO1 - 0.45 - VVOLFM+ (4) Output low level voltage for an FT I/O pin in FM+ mode (FT I/O with _f option) |IIO| = 20 mA 

VDDIO1 ≥ 2.7 V - 0.4 V|I IO | = 9 mA 

VDDIO1 ≥ VDD(min) - 0.4 1. The IIO current sourced or sunk by the device must always respect the absolute maximum rating specified in Table 18: Voltage characteristics , and the sum of the currents sourced or sunk by all the I/Os (I/O ports and control pins) must always respect the absolute maximum ratings ΣIIO. 2. As PC13, PC14 and PC15 are supplied through the power switch, the sum of currents sourced by those I/Os must not exceed 3 mA. 3. TTL and CMOS outputs are compatible with JEDEC standards JESD36 and JESD52. 4. Specified by design. Not tested in production. Electrical characteristics STM32G071x8/xB 

84/143 DS12232 Rev 5 

Table 53. Non-FT_c I/O output timing characteristics (1)(2) Speed Symbol Parameter Conditions Min Max Unit 

00 fmax Maximum frequency C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 2MHz C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 0.35 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 3C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 0.45 tr/t f Output rise and fall time C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 100 ns C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 225 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 75 C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 150 01 fmax Maximum frequency C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 10 MHz C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 2C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 15 C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 2.5 tr/tf Output rise and fall time C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 30 ns C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 60 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 15 C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 30 10 fmax Maximum frequency C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 30 MHz C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 15 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 60 C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 30 tr/tf Output rise and fall time C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 11 ns C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 22 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 4C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 811 fmax Maximum frequency C=30 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 60 MHz C=30 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 30 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 80 (3) C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 40 tr/t f Output rise and fall time C=30 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 5.5 ns C=30 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 11 C=10 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 2.5 C=10 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 5Fm+ fmax Maximum frequency C=50 pF, 1.6 V ≤ VDDIO1 ≤ 3.6 V - 1 MHz tf Output fall time (4) - 5 ns 1. The I/O speed is configured with the OSPEEDRy[1:0] bitfield. The FM+ mode is configured through the SYSCFG_CFGR1 register. Refer to the reference manual RM0444 for the description of the GPIO port configuration. 2. Specified by design. Not tested in production. 3. This value represents the I/O capability but the maximum system frequency is limited to 64 MHz. 4. The fall time is defined between 70% and 30% of the output waveform, according to I 2C specification. DS12232 Rev 5 85/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 22. I/O AC characteristics definition 5.3.15 NRST input characteristics 

The NRST input driver uses CMOS technology. It is connected to a permanent 

pull-up resistor, RPU. Unless otherwise specified, the parameters given in the following table are derived from tests performed under the ambient temperature and supply voltage conditions summarized in Table 21: General operating conditions .

Table 54. FT_c I/O output timing characteristics (1)(2) Speed Symbol Parameter Conditions Min Max Unit 

0fmax Maximum frequency C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 2 MHz C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 1tr/t f Output rise and fall time C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 170 ns C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 330 1fmax Maximum frequency C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 10 MHz C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 5tr/tf Output rise and fall time C=50 pF, 2.7 V ≤ VDDIO1 ≤ 3.6 V - 35 ns C=50 pF, 1.6 V ≤ VDDIO1 ≤ 2.7 V - 65 1. The I/O speed is configured using the OSPEEDRy[0] bit. Refer to the reference manual RM0444 for description of the GPIO port configuration. 2. Specified by design. Not tested in production.   

> MS32132V4 Maximum frequency is achieved with a duty cycle at (45 - 55%) when loaded by the specified capacitance. T10% 50% 90% 10% 50% 90% r(IO)out tf(IO)out t

Table 55. NRST pin characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

VIL(NRST) NRST input low level voltage - - - 0.3 x VDDIO1 VVIH(NRST) NRST input high level voltage - 0.7 x VDDIO1 - - VVhys(NRST) NRST Schmitt trigger voltage hysteresis - - 200 - mV Electrical characteristics STM32G071x8/xB 

86/143 DS12232 Rev 5 

Figure 23. Recommended NRST pin protection 

1. The reset network protects the device against parasitic resets. 2. The user must ensure that, upon power-on, the level on the NRST pin can exceed the minimum V IH(NRST) level. Otherwise, the device does not exit the power-on reset. This applies to any PF2-NRST configuration set, the GPIO mode inclusive. 3. The external capacitor on NRST must be placed as close as possible to the device. 

## 5.3.16 Extended interrupt and event controller input (EXTI) characteristics 

The pulse on the interrupt input must equal or exceed the minimum length, to guarantee that it is detected by the event controller. RPU Weak pull-up equivalent resistor (2) VIN = V SS 25 40 55 kΩ

VF(NRST) NRST input filtered pulse - - - 70 ns VNF(NRST) NRST input not filtered pulse 1.7 V ≤ VDD ≤ 3.6 V 350 - - ns 1. Specified by design. Not tested in production. 2. The pull-up is designed with a true resistance in series with a switchable PMOS. This PMOS contribution to the series resistance is minimal (~10% order). 

Table 55. NRST pin characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit 

> MS19878V4

RPU VDD Internal reset External reset circuit (1) NRST (2) Filter 0.1 μF (3) 

Table 56. EXTI input characteristics (1) 

1. Specified by design. Not tested in production. 

Symbol Parameter Min Typ Max Unit 

PLEC Pulse length to event controller 20 - - ns DS12232 Rev 5 87/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.17 Analog switch booster 

## 5.3.18 Analog-to-digital converter characteristics 

Unless otherwise specified, the parameters given in Table 58 are preliminary values derived from tests performed under ambient temperature, f PCLK frequency and V DDA supply voltage conditions summarized in Table 21: General operating conditions .

Note: It is recommended to perform a calibration after each power-up. 

Table 57. Analog switch booster characteristics (1)  

> 1. Specified by design. Not tested in production.

Symbol Parameter Min Typ Max Unit 

VDD Supply voltage 1.62 V - 3.6 VtSU(BOOST) Booster startup time - - 240 μs IDD(BOOST) Booster consumption for 

1.62 V ≤ VDD ≤ 2.0 V - - 250 μA Booster consumption for 

2.0 V ≤ VDD ≤ 2.7 V - - 500 Booster consumption for 

2.7 V ≤ VDD ≤ 3.6 V - - 900 

Table 58. ADC characteristics (1) Symbol Parameter Conditions (2) Min Typ Max Unit 

VDDA Analog supply voltage - 1.62 - 3.6 VVREF+ Positive reference voltage VDDA ≥ 2 V 2 - VDDA VVDDA < 2 V VDDA fADC ADC clock frequency Range 1 0.14 - 35 MHz Range 2 0.14 - 16 DADC (3) ADC analog clock duty cycle - 45 - 55 %fs Sampling rate 12 bits - - 2.50 MSps 10 bits - - 2.92 8 bits - - 3.50 6 bits - - 4.38 fTRIG External trigger frequency fADC = 35 MHz; 12 bits - - 2.33 MHz 12 bits - - fADC /15 VAIN (4) Conversion voltage range - VSSA - VREF+ VRAIN External input impedance - - - 50 kΩ

CADC Internal sample and hold capacitor - - 5 - pF Electrical characteristics STM32G071x8/xB 

88/143 DS12232 Rev 5 

tSTAB ADC power-up time - 2 Conversion cycle tCAL Calibration time fADC = 35 MHz 2.35 μs - 82 1/f ADC WLATENCY ADC_DR register write latency CKMODE[1:0] = 00 1.5 f ADC + 2 f PCLK cycles - 1.5 f ADC + 3 f PCLK cycles -CKMODE[1:0] = 01 - 4.5 -1/fPCLK CKMODE[1:0] = 10 - 8.5 -CKMODE[1:0] = 11 - 2.5 -tLATR Trigger conversion latency CKMODE[1:0] = 00 2 - 3 1/f ADC CKMODE[1:0] = 01 6.5 1/f PCLK CKMODE[1:0] = 10 12.5 CKMODE[1:0] = 11 3.5 ts Sampling time fADC = 35 MHz; VDDA > 2V 0.043 - 4.59 μs 1.5 - 160.5 1/f ADC fADC = 35 MHz; VDDA < 2V 0.1 - 4.59 μs 3.5 160.5 1/fADC tADCVREG_STUP ADC voltage regulator start-up time - - - 20 μs tCONV Total conversion time 

(including sampling time) fADC = 35 MHz Resolution = 12 bits 0.40 - 4.95 μs Resolution = 12 bits ts + 12.5 cycles for successive approximation = 14 to 173 1/fADC tIDLE Laps of time allowed between two conversions without rearm - - - 100 μs IDDA(ADC) ADC consumption from V DDA fs = 2.5 MSps - 410 -μA fs = 1 MSps - 164 -fs = 10 kSps - 17 -IDDV(ADC) ADC consumption from V REF+ fs = 2.5 MSps - 65 -μA fs = 1 MSps - 26 -fs = 10 kSps - 0.26 -1. Specified by design. Not tested in production. 2. I/O analog switch voltage booster must be enabled (BOOSTEN = 1 in the SYSCFG_CFGR1) when VDDA < 2.4 V and disabled when V DDA ≥ 2.4 V. 3. This requirement is granted when the incoming clock (PCLK or ADC asynchronous clock) is divided by two or more in the ADC. For other cases, refer to the reference manual section ADC clock for information on how to fulfill this requirement. 

Table 58. ADC characteristics (1) (continued) Symbol Parameter Conditions (2) Min Typ Max Unit DS12232 Rev 5 89/143 

STM32G071x8/xB Electrical characteristics  

> 110
> 4.

VREF+ is internally connected to VDDA on some packages.Refer to Section 4: Pinouts, pin description and alternate functions for further details. 

Table 59. Maximum ADC RAIN . Resolution Sampling cycle at 35 MHz Sampling time at 35 MHz [ns] Max. RAIN (1)(2) (Ω)

12 bits 1.5 (3) 43 50 3.5 100 680 7.5 214 2200 12.5 357 4700 19.5 557 8200 39.5 1129 15000 79.5 2271 33000 160.5 4586 50000 10 bits 1.5 (3) 43 68 3.5 100 820 7.5 214 3300 12.5 357 5600 19.5 557 10000 39.5 1129 22000 79.5 2271 39000 160.5 4586 50000 8 bits 1.5 (3) 43 82 3.5 100 1500 7.5 214 3900 12.5 357 6800 19.5 557 12000 39.5 1129 27000 79.5 2271 50000 160.5 4586 50000 Electrical characteristics STM32G071x8/xB 

90/143 DS12232 Rev 5 

6 bits 1.5 (3) 43 390 3.5 100 2200 7.5 214 5600 12.5 357 10000 19.5 557 15000 39.5 1129 33000 79.5 2271 50000 160.5 4586 50000 1. Specified by design. Not tested in production. 2. I/O analog switch voltage booster must be enabled (BOOSTEN = 1 in the SYSCFG_CFGR1) when V DDA < 2.4 V and disabled when VDDA ≥ 2.4 V. 3. Only allowed with VDDA > 2 V 

Table 59. Maximum ADC RAIN . (continued) Resolution Sampling cycle at 35 MHz Sampling time at 35 MHz [ns] Max. RAIN (1)(2) (Ω)

Table 60. ADC accuracy (1)(2)(3) Symbol Parameter Conditions (4) Min Typ Max Unit 

ET Total unadjusted error VDDA = V REF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C - ±3 ±4 LSB 2 V < V DDA =V REF+ < 3.6 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = entire range - ±3 ±6.5 1.65 V < V DDA =V REF+ < 3.6 V; 

TA = entire range 

Range 1: f ADC = 35 MHz; f s ≤ 2.2 MSps; 

Range 2: f ADC = 16 MHz; f s ≤ 1.1 MSps; - ±3 ±7.5 EO Offset error VDDA = VREF+ = 3 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = 25 °C - ±1.5 ±2 LSB 2 V < VDDA = VREF+ < 3.6 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = entire range - ±1.5 ±4.5 1.65 V < VDDA=VREF+ < 3.6 V; 

TA = entire range 

Range 1: fADC = 35 MHz; fs ≤ 2.2 MSps; 

Range 2: fADC = 16 MHz; fs ≤ 1.1 MSps; - ±1.5 ±5.5 DS12232 Rev 5 91/143 

STM32G071x8/xB Electrical characteristics 

> 110

EG Gain error VDDA = V REF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C - ±3 ±3.5 LSB 2 V < V DDA = V REF+ < 3.6 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = entire range - ±3 ±5 1.65 V < V DDA = V REF+ < 3.6 V; 

TA = entire range 

Range 1: f ADC = 35 MHz; f s ≤ 2.2 MSps; 

Range 2: f ADC = 16 MHz; f s ≤ 1.1 MSps; - ±3 ±6.5 ED Differential linearity error VDDA = VREF+ = 3 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = 25 °C - ±1.2 ±1.5 LSB 2 V < VDDA = VREF+ < 3.6 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = entire range - ±1.2 ±1.5 1.65 V < VDDA = VREF+ < 3.6 V; 

TA = entire range 

Range 1: fADC = 35 MHz; fs ≤ 2.2 MSps; 

Range 2: fADC = 16 MHz; fs ≤ 1.1 MSps; - ±1.2 ±1.5 EL Integral linearity error VDDA = V REF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C - ±2.5 ±3 LSB 2 V < V DDA = V REF+ < 3.6 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = entire range - ±2.5 ±3 1.65 V < V DDA = V REF+ < 3.6 V; 

TA = entire range 

Range 1: fADC = 35 MHz; fs ≤ 2.2 MSps; 

Range 2: f ADC = 16 MHz; f s ≤ 1.1 MSps; - ±2.5 ±3.5 ENOB Effective number of bits VDDA = VREF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C 10.1 10.2 -bit 2 V < VDDA = VREF+ < 3.6 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = entire range 9.6 10.2 -1.65 V < VDDA = VREF+ < 3.6 V; 

TA = entire range 

Range 1: f ADC = 35 MHz; f s ≤ 2.2 MSps; 

Range 2: fADC = 16 MHz; fs ≤ 1.1 MSps; 9.5 10.2 -

Table 60. ADC accuracy (1)(2)(3) (continued) Symbol Parameter Conditions (4) Min Typ Max Unit Electrical characteristics STM32G071x8/xB 

92/143 DS12232 Rev 5 

SINAD Signal-to-noise and distortion ratio VDDA = V REF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C 62.5 63 -dB 2 V < V DDA = V REF+ < 3.6 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = entire range 59.5 63 -1.65 V < V DDA = V REF+ < 3.6 V; 

TA = entire range 

Range 1: f ADC = 35 MHz; f s ≤ 2.2 MSps; 

Range 2: f ADC = 16 MHz; f s ≤ 1.1 MSps; 59 63 -SNR Signal-to-noise ratio VDDA = VREF+ = 3 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = 25 °C 63 64 -dB 2 V < VDDA = VREF+ < 3.6 V; 

fADC = 35 MHz; f s ≤ 2.5 MSps; 

TA = entire range 60 64 -1.65 V < VDDA = VREF+ < 3.6 V; 

TA = entire range 

Range 1: fADC = 35 MHz; fs ≤ 2.2 MSps; 

Range 2: fADC = 16 MHz; fs ≤ 1.1 MSps; 60 64 -THD Total harmonic distortion VDDA = V REF+ = 3 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = 25 °C - -74 -73 dB 2 V < V DDA = V REF+ < 3.6 V; 

fADC = 35 MHz; fs ≤ 2.5 MSps; 

TA = entire range - -74 -70 1.65 V < V DDA = V REF+ < 3.6 V; 

TA = entire range 

Range 1: fADC = 35 MHz; fs ≤ 2.2 MSps; 

Range 2: f ADC = 16 MHz; f s ≤ 1.1 MSps; - -74 -70 1. Based on characterization results, not tested in production. 2. ADC DC accuracy values are measured after internal calibration. 3. Injecting negative current on any analog input pin significantly reduces the accuracy of A-to-D conversion of signal on another analog input. It is recommended to add a Schottky diode (pin to ground) to analog pins susceptible to receive negative current. 4. I/O analog switch voltage booster enabled (BOOSTEN = 1 in the SYSCFG_CFGR1) when VDDA < 2.4 V and disabled when V DDA ≥ 2.4 V. 

Table 60. ADC accuracy (1)(2)(3) (continued) Symbol Parameter Conditions (4) Min Typ Max Unit DS12232 Rev 5 93/143 

STM32G071x8/xB Electrical characteristics 

110 

Figure 24. ADC accuracy characteristics Figure 25. ADC typical connection diagram 

1. Refer to Table 58: ADC characteristics for the values of RAIN and CADC. 2. Cparasitic represents the capacitance of the PCB (dependent on soldering and PCB layout quality) plus the pad capacitance (refer to Table 51: I/O static characteristics for the value of the pad capacitance). A high Cparasitic value downgrades conversion accuracy. To remedy this, fADC should be reduced. 3. Refer to Table 51: I/O static characteristics for the values of Ilkg. 4. Refer to Figure 13: Power supply scheme .

General PCB design guidelines 

Power supply decoupling should be performed as shown in Figure 13: Power supply scheme . The 100 nF capacitor should be ceramic (good quality) and it should be placed as close as possible to the chip. 

MSv19880V6 (1) Example of an actual transfer curve (2) Ideal transfer curve (3) End-point correlation line n = ADC resolution ET = total unadjusted error: maximum deviation between the actual and ideal transfer curves EO = offset error: maximum deviation between the first actual transition and the first ideal one EG = gain error: deviation between the last ideal transition and the last actual one ED = differential linearity error: maximum deviation between actual steps and the ideal one EL = integral linearity error: maximum deviation between any actual transition and the end point correlation line 2n-1 76543210(1/2 n)*VREF+ Output code EO VSSA 2n-2 2n-3 VREF+ (VDDA) ET EL ED 1 LSB ideal EG (1) (2) (3) (or )] [1LSB = VDDA 2nVREF+ 2n(2/2 n)*VREF+ (3/2 n)*VREF+ (4/2 n)*VREF+ (5/2 n)*VREF+ (6/2 n)*VREF+ (7/2 n)*VREF+ (2 n-3 /2 n)*VREF+ (2 n-2 /2 n)*VREF+ (2 n-1 /2 n)*VREF+ (2 n/2 n)*VREF+ 

MSv67871V3 Sample-and-hold ADC converter Converter Cparasitic (2) Ilkg (3) CADC VDDA (4) RAIN (1) VAIN RADC VREF+ (4) VSSA I/O analog switch Sampling switch with multiplexing VSS VSS Electrical characteristics STM32G071x8/xB 

94/143 DS12232 Rev 5 

## 5.3.19 Digital-to-analog converter characteristics 

Table 61. DAC characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

VDDA Analog supply voltage for DAC ON DAC output buffer OFF, DAC_OUT pin not connected (internal connection only) 1.71 -3.6 VOther modes 1.80 -VREF+ Positive reference voltage DAC output buffer OFF, DAC_OUT pin not connected (internal connection only) 1.71 -VDDA VOther modes 1.80 -RL Resistive load DAC output buffer ON connected to V SSA 5 - - kΩ

connected to V DDA 25 - -RO Output Impedance DAC output buffer OFF 9.6 11.7 13.8 kΩ

RBON Output impedance sample and hold mode, output buffer ON VDD = 2.7 V - - 2kΩ

VDD = 2.0 V - - 3.5 RBOFF Output impedance sample and hold mode, output buffer OFF VDD = 2.7 V - - 16.5 kΩ

VDD = 2.0 V - - 18.0 CL Capacitive load DAC output buffer ON - - 50 pF CSH Sample and hold mode - 0.1 1 μF VDAC_OUT Voltage on DAC_OUT output DAC output buffer ON 0.2 - VREF+ – 0.2 VDAC output buffer OFF 0 - VREF+ tSETTLING Settling time (full scale: for a 12-bit code transition between the lowest and the highest input codes when DAC_OUT reaches final value ±0.5LSB, ±1 LSB, ±2 LSB, ±4 LSB, ±8 LSB) Normal mode 

DAC output buffer ON 

CL ≤ 50 pF, 

RL ≥ 5 k Ω

±0.5 LSB - 1.7 3μs ±1 LSB - 1.6 2.9 ±2 LSB - 1.55 2.85 ±4 LSB - 1.48 2.8 ±8 LSB - 1.4 2.75 Normal mode DAC output buffer OFF, ±1LSB, CL = 10 pF - 2 2.5 tWAKEUP (2) Wakeup time from off state (setting the ENx bit in the DAC Control register) until final value ±1 LSB Normal mode DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω - 4.2 7.5 μs Normal mode DAC output buffer OFF, CL ≤ 10 pF - 2 5PSRR VDDA supply rejection ratio Normal mode DAC output buffer ON 

CL ≤ 50 pF, RL = 5 k Ω, DC - -80 -28 dB DS12232 Rev 5 95/143 

STM32G071x8/xB Electrical characteristics 

> 110

TW_to_W Minimum time between two consecutive writes into the DAC_DORx register to guarantee a correct DAC_OUT for a small variation of the input code (1 LSB) DAC_MCR:MODEx[2:0] = 000 or 001 

CL ≤ 50 pF; RL ≥ 5 k Ω

1 - -μs DAC_MCR:MODEx[2:0] = 010 or 011 

CL ≤ 10 pF 1.4 - -tSAMP Sampling time in sample and hold mode (code transition between the lowest input code and the highest input code when DACOUT reaches final value ±1LSB) DAC_OUT pin connected DAC output buffer ON, C SH = 100 nF - 0.7 3.5 ms DAC output buffer OFF, CSH = 100 nF - 10.5 18 DAC_OUT pin not connected (internal connection only) DAC output buffer OFF - 2 3.5 μs Ileak Output leakage current Sample and hold mode, 

DAC_OUT pin connected - - -(3) nA CI int Internal sample and hold capacitor - 5.2 7 8.8 pF tTRIM Middle code offset trim time DAC output buffer ON 50 - - μs Voffset Middle code offset for 1 trim code step VREF+ = 3.6 V - 1500 - μV VREF+ = 1.8 V - 750 -IDDA(DAC) DAC consumption from VDDA DAC output buffer ON No load, middle code (0x800) - 315 500 μA No load, worst code (0xF1C) - 450 670 DAC output buffer OFF No load, middle code (0x800) - - 0.2 Sample and hold mode, C SH =100 nF -315 ₓ

Ton/(Ton+ Toff )(4) 670 ₓ

Ton/(Ton+ Toff )(4) 

Table 61. DAC characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit Electrical characteristics STM32G071x8/xB 

96/143 DS12232 Rev 5 

Figure 26. 12-bit buffered / non-buffered DAC 

1. The DAC integrates an output buffer that can be used to reduce the output impedance and to drive external loads directly without the use of an external operational amplifier. The buffer can be bypassed by configuring the BOFFx bit in the DAC_CR register. .IDDV(DAC) DAC consumption from VREF+ DAC output buffer ON No load, middle code (0x800) - 185 240 μA No load, worst code (0xF1C) - 340 400 DAC output buffer OFF No load, middle code (0x800) - 155 205 Sample and hold mode, buffer ON, CSH = 100 nF, worst case -185 ₓ

Ton/(Ton+ Toff )(4) 400 ₓ

Ton/(Ton+ Toff )(4) Sample and hold mode, buffer OFF, CSH = 100 nF, worst case -155 ₓ

Ton/(Ton+ Toff )(4) 205 ₓ

Ton/(Ton+ Toff )(4) 1. Specified by design. Not tested in production. 2. In buffered mode, the output can overshoot above the final value for low input code (starting from min value). 3. Refer to Table 51: I/O static characteristics .4. Ton is the Refresh phase duration. Toff is the Hold phase duration. Refer to RM0444 reference manual for more details. 

Table 61. DAC characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit 

> MSv47959V1

12-bit digital-to-analog converter Buffered / non-buffered DAC DAC_OUTx RLOAD CLOAD Buffer (1) 

Table 62. DAC accuracy (1) Symbol Parameter Conditions Min Typ Max Unit 

DNL Differential non linearity (2) DAC output buffer ON - - ±2 LSB DAC output buffer OFF - - ±2 - monotonicity 10 bits guaranteed LSB DS12232 Rev 5 97/143 

STM32G071x8/xB Electrical characteristics 

> 110

INL Integral non linearity (3) DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω - - ±4 LSB DAC output buffer OFF 

CL ≤ 50 pF, no RL - - ±4 Offset Offset error at code 0x800 (3) DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω

VREF+ = 3.6 V - - ±12 LSB VREF+ = 1.8 V - - ±25 DAC output buffer OFF 

CL ≤ 50 pF, no RL - - ±8 Offset1 Offset error at code 0x001 (4) DAC output buffer OFF 

CL ≤ 50 pF, no RL - - ±5 LSB OffsetCal Offset Error at code 0x800 after calibration DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω

VREF+ = 3.6 V - - ±5 LSB VREF+ = 1.8 V - - ±7 Gain Gain error (5) DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω - - ±0.5 %DAC output buffer OFF 

CL ≤ 50 pF, no RL - - ±0.5 TUE Total unadjusted error DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω - - ±30 LSB DAC output buffer OFF 

CL ≤ 50 pF, no RL - - ±12 TUECal Total unadjusted error after calibration DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω - - ±23 LSB SNR Signal-to-noise ratio DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω

1 kHz, BW 500 kHz - 71.2 -dB DAC output buffer OFF 

CL ≤ 50 pF, no RL, 1 kHz 

BW 500 kHz - 71.6 -THD Total harmonic distortion DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω, 1 kHz - -78 -dB DAC output buffer OFF 

CL ≤ 50 pF, no RL, 1 kHz - -79 -SINAD Signal-to-noise and distortion ratio DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω, 1 kHz - 70.4 -dB DAC output buffer OFF 

CL ≤ 50 pF, no RL, 1 kHz - 71 -

Table 62. DAC accuracy (1) (continued) Symbol Parameter Conditions Min Typ Max Unit Electrical characteristics STM32G071x8/xB 

98/143 DS12232 Rev 5 

## 5.3.20 Voltage reference buffer characteristics 

ENOB Effective number of bits DAC output buffer ON 

CL ≤ 50 pF, RL ≥ 5 k Ω, 1 kHz - 11.4 -bits DAC output buffer OFF 

CL ≤ 50 pF, no RL, 1 kHz - 11.5 -1. Specified by design. Not tested in production. 2. Difference between two consecutive codes - 1 LSB. 3. Difference between measured value at Code i and the value at Code i on a line drawn between Code 0 and last Code 4095. 4. Difference between the value measured at Code (0x001) and the ideal value. 5. Difference between ideal slope of the transfer function and measured slope computed from code 0x000 and 0xFFF when buffer is OFF, and from code giving 0.2 V and (V REF+ – 0.2) V when buffer is ON. 

Table 62. DAC accuracy (1) (continued) Symbol Parameter Conditions Min Typ Max Unit 

Table 63. VREFBUF characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

VDDA VREFBUF operating voltage VRS = 0 2.4 - 3.6 VVRS = 1 2.8 - 3.6 VREFBUF_ OUT Voltage reference output Iload =

100 μA T = 30 °C VRS = 0 2.038 (2) 2.042 2.046 VVRS = 1 2.497 (2) 2.5 2.503 TRIM Trim step resolution - - ±0.05 ±0.1 %CL Load capacitor - 0.5 1 1.5 μF esr Equivalent Serial Resistor of C load - - - 2 Ω

Iload Static load current - - - 4 mA Iline_reg Line regulation 2.8 V ≤ VDDA ≤ 3.6 V Iload = 500 μA - 200 1000 ppm/V Iload = 4 mA - 100 500 Iload_reg Load regulation 500 μA ≤ Iload ≤4 mA Normal mode - 50 500 ppm/mA TCoeff_vrefbuf Temperature coefficient of VREFBUF (3) -40 °C < TJ < +125 °C - - 50 ppm/ °C PSRR Power supply rejection DC 40 60 - dB 100 kHz 25 40 -tSTART Start-up time CL = 0.5 μF (4) - 300 350 μs CL = 1.1 μF (4) - 500 650 CL = 1.5 μF (4) - 650 800 DS12232 Rev 5 99/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.21 Comparator characteristics 

IINRUSH Control of maximum DC current drive on VREFBUF_OUT during start-up phase (5) - - 8 - mA IDDA(VREFBU F) VREFBUF consumption from V DDA Iload = 0 μA - 16 25 μA Iload = 500 μA - 18 30 Iload = 4 mA - 35 50 1. Specified by design. Not tested in production. 2. If the V DDA is below the VREFBUF operating voltage, the voltage reference buffer can not maintain accurately the output voltage and it could drop down to VDDA - 150mV. 3. The temperature coefficient at VREF+ output is the sum of TCoeff_vrefint and TCoeff_vrefbuf. 4. The capacitive load must include a 100 nF capacitor in order to cut-off the high frequency noise. 5. To correctly control the VREFBUF inrush current during start-up phase and scaling change, the V DDA voltage should be in the range [2.4 V to 3.6 V] and [2.8 V to 3.6 V] respectively for VRS = 0 and VRS = 1. 

Table 63. VREFBUF characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit 

Table 64. COMP characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

VDDA Analog supply voltage - 1.62 - 3.6 VVIN Comparator 

input voltage range - 0 - VDDA VVBG (2) Scaler input voltage - VREFINT VVSC Scaler offset voltage - - ±5 ±10 mV IDDA(SCALER) Scaler static consumption from VDDA BRG_EN=0 (bridge disable) - 200 300 nA BRG_EN=1 (bridge enable) - 0.8 1 μA tSTART_SCALER Scaler startup time - - 100 200 μs tSTART Comparator startup time to reach propagation delay specification High-speed mode - - 5μs Medium-speed mode - - 15 tD Propagation delay 200 mV step; 100 mV overdrive High-speed mode - 30 50 ns Medium-speed mode - 0.3 0.6 μs >200 mV step; 100 mV overdrive High-speed mode - - 70 ns Medium-speed mode - - 1.2 μs Voffset Comparator offset error Full common mode range - ±5 ±20 mV Electrical characteristics STM32G071x8/xB 

100/143 DS12232 Rev 5 

## 5.3.22 Temperature sensor characteristics 

## 5.3.23 VBAT monitoring characteristics 

Vhys Comparator hysteresis No hysteresis - 0 -mV Low hysteresis - 10 -Medium hysteresis - 20 -High hysteresis - 30 -IDDA(COMP) Comparator consumption from VDDA Medium-speed 

mode Static - 5 7.5 μA With 50 kHz and ±100 mV overdrive square signal - 6 -High-speed mode Static - 250 400 With 50 kHz and ±100 mV overdrive square signal - 250 -1. Specified by design. Not tested in production. 2. Refer to Table 24: Embedded internal voltage reference .

Table 64. COMP characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit 

Table 65. TS characteristics Symbol Parameter Min Typ Max Unit 

TL (1) VTS linearity with temperature - ±1 ±2 °C Avg_Slope (2) Average slope 2.3 2.5 2.7 mV/°C V30 Voltage at 30°C (±5 °C) (3) 0.742 0.76 0.785 VtSTART(TS_BUF) (1) Sensor Buffer Start-up time in continuous mode (4) - 8 15 μs tSTART (1) Start-up time when entering in continuous mode (4) - 70 120 μs tS_temp (1) ADC sampling time when reading the temperature 5 - - μs IDD(TS) (1) Temperature sensor consumption from V DD , when selected by ADC - 4.7 7 μA 1. Specified by design. Not tested in production. 2. Based on characterization results, not tested in production. 3. Measured at VDDA = 3.0 V ±10 mV. The V30 ADC conversion result is stored in the TS_CAL1 byte. 4. Continuous mode means Run/Sleep modes, or temperature sensor enable in Low-power run/Low-power sleep modes. 

Table 66. VBAT monitoring characteristics Symbol Parameter Min Typ Max Unit 

R Resistor bridge for V BAT - 39 - kΩ

Q Ratio on VBAT measurement - 3 - -DS12232 Rev 5 101/143 

STM32G071x8/xB Electrical characteristics 

> 110

## 5.3.24 Timer characteristics 

The parameters given in the following tables are specified by design and not tested in production. Refer to Section 5.3.14: I/O port characteristics for details on the input/output alternate function characteristics (output compare, input capture, external clock, PWM output). Er (1) Error on Q -10 - 10 %tS_vbat (1) ADC sampling time when reading the VBAT 12 - - μs 1. Specified by design. Not tested in production. 

Table 66. VBAT monitoring characteristics (continued) Symbol Parameter Min Typ Max Unit 

Table 67. V BAT charging characteristics Symbol Parameter Conditions Min Typ Max Unit 

RBC Battery charging resistor VBRS = 0 - 5 -kΩ

VBRS = 1 - 1.5 -

Table 68. TIMx (1) characteristics Symbol Parameter Conditions Min Max Unit 

tres(TIM) Timer resolution time - 1 - tTIMxCLK fTIMxCLK = 64 MHz 15.625 - ns fEXT Timer external clock frequency on CH1 to CH4 - 0 fTIMxCLK /2 MHz fTIMxCLK = 64 MHz 0 40 ResTIM Timer resolution TIMx (except TIM2) - 16 bit TIM2 - 32 tCOUNTER 16-bit counter clock period - 1 65536 tTIMxCLK fTIMxCLK = 64 MHz 0.015625 1024 μs tMAX_COUNT Maximum possible count with 32-bit counter - - 65536 × 65536 tTIMxCLK fTIMxCLK = 64 MHz - 67.10 s1. TIMx is used as a general term to refer to a timer (for example, TIM1). Electrical characteristics STM32G071x8/xB 

102/143 DS12232 Rev 5 

## 5.3.25 Characteristics of communication interfaces I2C-bus interface characteristics 

The I 2C-bus interface meets timing requirements of the I 2C-bus specification and user manual rev. 03 for: 

• Standard-mode (Sm): with a bit rate up to 100 kbit/s 

• Fast-mode (Fm): with a bit rate up to 400 kbit/s 

• Fast-mode Plus (Fm+): with a bit rate up to 1 Mbit/s. The timings are ensured by design as long as the I2C peripheral is properly configured (refer to the reference manual RM0444) and when the I2CCLK frequency is greater than the minimum shown in the following table. The SDA and SCL I/O requirements are met with the following restrictions: the SDA and SCL I/O pins are not “true” open-drain. When configured as open-drain, the PMOS connected between the I/O pin and V DDIO1 is disabled, but is still present. Only FT_f I/O pins 

Table 69. IWDG min/max timeout period at 32 kHz LSI clock (1) Prescaler divider PR[2:0] bits Min timeout RL[11:0]= 0x000 Max timeout RL[11:0]= 0xFFF Unit 

/4 0 0.125 512 ms /8 1 0.250 1024 /16 2 0.500 2048 /32 3 1.0 4096 /64 4 2.0 8192 /128 5 4.0 16384 /256 6 or 7 8.0 32768 1. The exact timings further depend on the phase of the APB interface clock versus the LSI clock, which causes an uncertainty of one RC period. 

Table 70. Minimum I2CCLK frequency Symbol Parameter Condition Typ Unit 

fI2CCLK(min) Minimum I2CCLK frequency for correct operation of I2C peripheral Standard-mode 2MHz Fast-mode Analog filter enabled 9DNF = 0 Analog filter disabled 9DNF = 1 Fast-mode Plus Analog filter enabled 18 DNF = 0 Analog filter disabled 16 DNF = 1 DS12232 Rev 5 103/143 

STM32G071x8/xB Electrical characteristics 

> 110

support Fm+ low-level output current maximum requirement. Refer to Section 5.3.14: I/O port characteristics for the I2C I/Os characteristics. All I2C SDA and SCL I/Os embed an analog filter. Refer to the following table for its characteristics: 

SPI/I 2S characteristics 

Unless otherwise specified, the parameters given in Table 72 for SPI are derived from tests performed under the ambient temperature, f PCLKx frequency and supply voltage conditions summarized in Table 21: General operating conditions . The additional general conditions are: 

• OSPEEDRy[1:0] set to 11 (output speed) 

• capacitive load C = 30 pF 

• measurement points at CMOS levels: 0.5 x V DD Refer to Section 5.3.14: I/O port characteristics for more details on the input/output alternate function characteristics (NSS, SCK, MOSI, MISO for SPI). 

Table 71. I2C analog filter characteristics (1) Symbol Parameter Min Max Unit 

tAF Limiting duration of spikes suppressed by the filter (2) 50 260 ns 1. Based on characterization results, not tested in production. 2. Spikes shorter than the limiting duration are suppressed. 

Table 72. SPI characteristics (1) Symbol Parameter Conditions Min Typ Max Unit 

fSCK 1/t c(SCK) SPI clock frequency Master mode 

1.65 < V DD < 3.6 V 

Range 1 - -32 MHz Master transmitter 

1.65 < V DD < 3.6 V 

Range 1 32 Slave receiver 

1.65 < V DD < 3.6 V 

Range 1 32 Slave transmitter/full duplex 

2.7 < V DD < 3.6 V 

Range 1 32 Slave transmitter/full duplex 

1.65 < V DD < 3.6 V 

Range 1 23 1.65 < V DD < 3.6 V 

Range 2 8tsu(NSS) NSS setup time Slave mode, SPI prescaler = 2 4 ₓ TPCLK - - ns th(NSS) NSS hold time Slave mode, SPI prescaler = 2 2 ₓ TPCLK - - ns Electrical characteristics STM32G071x8/xB 

104/143 DS12232 Rev 5 

tw(SCKH) SCK high time Master mode TPCLK - 1.5 TPCLK TPCLK + 1.5 ns tw(SCKL) SCK low time Master mode TPCLK - 1.5 TPCLK TPCLK + 1.5 ns tsu(MI) Master data input setup time - 1 - - ns tsu(SI) Slave data input setup time - 1 - - ns th(MI) Master data input hold time - 5 - - ns th(SI) Slave data input hold time - 1 - - ns ta(SO) Data output access time Slave mode 9 - 34 ns tdis(SO) Data output disable time Slave mode 9 - 16 ns tv(SO) Slave data output valid time 2.7 < V DD < 3.6 V 

Range 1 - 9 14 ns 1.65 < VDD < 3.6 V 

Range 1 - 9 21 1.65 < VDD < 3.6 V 

Voltage Range 2 - 11 24 tv(MO) Master data output valid time - - 3 5 ns th(SO) Slave data output hold time - 5 - - ns th(MO) Master data output hold time - 1 - - ns 1. Based on characterization results, not tested in production. 

Table 72. SPI characteristics (1) (continued) Symbol Parameter Conditions Min Typ Max Unit DS12232 Rev 5 105/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 27. SPI timing diagram - slave mode and CPHA = 0 Figure 28. SPI timing diagram - slave mode and CPHA = 1 

> MSv41658V2

NSS input CPHA=0 CPOL=0 SCK input CPHA=0 CPOL=1 MISO output MOSI input tsu(SI) th(SI) tw(SCKL) tw(SCKH) tc(SCK) th(NSS) tdis(SO) tsu(NSS) ta(SO) tv(SO) Next bits IN Last bit OUT First bit IN First bit OUT Next bits OUT th(SO) Last bit IN 

> MSv41659V2

th(SI) tc(SCK) tw(SCKH) tw(SCKL) tsu(NSS) ta(SO) tv(SO) th(NSS) tdis(SO) tsu(SI) NSS input CPHA=1 CPOL=0 CPHA=1 CPOL=1 MISO output MOSI input SCK input First bit OUT Next bits OUT Last bit OUT First bit IN Last bit IN Next bits IN th(SO) Electrical characteristics STM32G071x8/xB 

106/143 DS12232 Rev 5 

Figure 29. SPI timing diagram - master mode    

> MSv72626V1 th(MI) tc(SCK) tw(SCKH) tw(SCKL) tsu(MI) NSS input CPHA=0 CPOL=0 CPHA=0 CPOL=1 MOSI output MISO input SCK output First bit OUT Last bit OUT Next bits OUT First bit IN Last bit IN Next bits IN CPHA=1 CPOL=0 CPHA=1 CPOL=1 SCK output High tv(MO) th(MO)

Table 73. I 2S characteristics (1) Symbol Parameter Conditions Min Max Unit 

fMCK I2S main clock output fMCK= 256 x Fs; (Fs = audio sampling frequency) 

Fs min = 8 kHz; Fs max = 192 kHz; 2.048 49.152 MHz fCK I2S clock frequency Master data - 64xFs MHz Slave data - 64xFs DCK I2S clock frequency duty cycle Slave receiver 30 70 %tv(WS) WS valid time Master mode - 8 ns th(WS) WS hold time Master mode 2 - ns tsu(WS) WS setup time Slave mode 4 - ns th(WS) WS hold time Slave mode 2 - ns tsu(SD_MR) Data input setup time Master receiver 4 - ns tsu(SD_SR) Slave receiver 5 - ns th(SD_MR) Data input hold time Master receiver 4.5 - ns th(SD_SR) Slave receiver 2 - ns tv(SD_ST) Data output valid time -slave transmitter after enable edge; 2.7 < VDD < 3.6V -16 ns after enable edge; 1.65 < VDD < 3.6V 23 tv(SD_MT) Data output valid time -master transmitter after enable edge - 5.5 ns DS12232 Rev 5 107/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 30. I 2S slave timing diagram (Philips protocol) 

1. Measurement points are done at CMOS levels: 0.3 VDDIO1 and 0.7 VDDIO1. 2. LSB transmit/receive of the previously transmitted byte. No LSB transmit/receive is sent before the first byte. th(SD_ST) Data output hold time -slave transmitter after enable edge 8 - ns th(SD_MT) Data output hold time -master transmitter after enable edge 1 - ns 1. Based on characterization results, not tested in production. 

Table 73. I 2S characteristics (1) (continued) Symbol Parameter Conditions Min Max Unit 

> MSv39721V1 CK Input

CPOL = 0 CPOL = 1 tc(CK) WS input SDtransmit SDreceive tw(CKH) tw(CKL) tsu(WS) tv(SD_ST) th(SD_ST) th(WS) tsu(SD_SR) th(SD_SR) MSB receive Bitn receive LSB receive MSB transmit Bitn transmit LSB receive(2) LSB transmit(2) Electrical characteristics STM32G071x8/xB 

108/143 DS12232 Rev 5 

Figure 31. I 2S master timing diagram (Philips protocol)   

> 1. Based on characterization results, not tested in production. 2. LSB transmit/receive of the previously transmitted byte. No LSB transmit/receive is sent before the first byte.

USART (SPI mode) characteristics 

Unless otherwise specified, the parameters given in Table 74 for USART are derived from tests performed under the ambient temperature, f PCLKx frequency and supply voltage conditions summarized in Table 21: General operating conditions . The additional general conditions are: 

• OSPEEDRy[1:0] set to 10 (output speed) 

• capacitive load C = 30 pF 

• measurement points at CMOS levels: 0.5 x V DD Refer to Section 5.3.14: I/O port characteristics for more details on the input/output alternate function characteristics (NSS, CK, TX, and RX for USART).       

> MSv39720V1 CK output  CPOL = 0 CPOL = 1 tc(CK) WS output SDreceive SDtransmit tw(CKH) tw(CKL) tsu(SD_MR) tv(SD_MT) th(SD_MT) th(WS) th(SD_MR) MSB receive Bitn receive LSB receive MSB transmit Bitn transmit LSB transmit tf(CK) tr(CK) tv(WS) LSB receive(2) LSB transmit(2) 10% 90%

Table 74. USART characteristics in SPI mode Symbol Parameter Conditions Min Typ Max Unit 

fCK USART clock frequency Master mode - - 8 MHz Slave mode - - 21 tsu(NSS) NSS setup time Slave mode Tker (1) + 2 - - ns th(NSS) NSS hold time Slave mode 2 - - ns DS12232 Rev 5 109/143 

STM32G071x8/xB Electrical characteristics 

> 110

Figure 32. USART timing diagram in SPI master mode 

tw(CKH) CK high time Master mode 1 / f CK / 2 - 1 1 / f CK / 2 1 / f CK / 2 + 1 ns tw(CKL) CK low time ns tsu(RX) Data input setup time Master mode Tker (1) + 2 - - ns Slave mode 4 - - ns th(RX) Data input hold time Master mode 1 - - ns Slave mode 0.5 - - ns tv(TX) Data output valid time Master mode - 0.5 1 ns Slave mode - 10 19 ns th(TX) Data output hold time Master mode 0 - - ns Slave mode 7 - - ns 1. Tker is the usart_ker_ck_pres clock period 

Table 74. USART characteristics in SPI mode Symbol Parameter Conditions Min Typ Max Unit 

> MSv65386V6

1/fCK tw(CKH) tw(CKL) CPHA=0 CPOL=0 CPHA=0 CPOL=1 TX output RX input CK output MSB OUT LSB OUT BIT1 OUT MSB IN LSB IN BIT6 IN CPHA=1 CPOL=0 CPHA=1 CPOL=1 CK output tsu(RX) tv(TX) th(TX) th(RX) Electrical characteristics STM32G071x8/xB 

110/143 DS12232 Rev 5 

Figure 33. USART timing diagram in SPI slave mode UCPD characteristics 

UCPD1 and UCPD2 controllers comply with USB Type-C Rev.2 and USB Power Delivery Rev. 3.0 specifications.   

> MSv65387V6 NSS input CPHA=0 CPOL=0 CK input CPHA=0 CPOL=1 TX output RX input th(RX) tw(CKL) tw(CKH) 1/fCK th(NSS) tsu(NSS) tv(TX) Next bits IN Last bit OUT First bit IN First bit OUT Next bits OUT th(TX) Last bit IN tsu(RX)

Table 75. UCPD operating conditions Symbol Parameter Conditions Min Typ Max Unit 

VDD UCPD operating supply voltage Sink mode only 3.0 3.3 3.6 VSink and source mode 3.135 3.3 3.465 Vswing Output voltage swing - 1.05 - 1.2 VZDRV Output driver impedance Driving high or low 33 - 75 ΩDS12232 Rev 5 111/143 

STM32G071x8/xB Package information 

> 135

# 6 Package information 

In order to meet environmental requirements, ST offers these devices in different grades of ECOPACK packages, depending on their level of environmental compliance. ECOPACK specifications, grade definitions and product status are available at: www.st.com .ECOPACK is an ST trademark. 

# 6.1 Device marking 

Refer to technical note “Reference device marking schematics for STM32 microcontrollers and microprocessors” (TN1433) available on www.st.com , for the location of pin 1 / ball A1 as well as the location and orientation of the marking areas versus pin 1 / ball A1. Parts marked as “ES”, “E” or accompanied by an engineering sample notification letter, are not yet qualified and therefore not approved for use in production. ST is not responsible for any consequences resulting from such use. In no event will ST be liable for the customer using any of these engineering samples in production. ST’s Quality department must be contacted prior to any decision to use these engineering samples to run a qualification activity. A WLCSP simplified marking example (if any) is provided in the corresponding package information subsection. Package information STM32G071x8/xB 

112/143 DS12232 Rev 5 

# 6.2 WLCSP25 package information Figure 34. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip scale package outline 

1. Drawing is not to scale. 2. Dimension is measured at the maximum bump diameter parallel to primary datum Z. 3. Primary datum Z and seating plane are defined by the spherical crowns of the bump. 4. Bump position designation per JESD 95-1, SPP-010. 

Table 76. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip scale mechanical data Symbol millimeters inches (1) Min Typ Max Min Typ Max 

A(2) - - 0.59 - - 0.023 A1 - 0.18 - - 0.007 -A2 - 0.38 - - 0.015 -A3 - 0.025 (3) - - 0.001 -b 0.22 0.25 0.28 0.009 0.010 0.011 D 2.28 2.30 2.32 0.090 0.091 0.091 E 2.46 2.48 2.50 0.097 0.098 0.098 

> A06J_WLCSP25_ME_V1

ZABCDE2 1345Geee2 e1 FA1 ball location DEaaa (4X) BOTTOM VIEW TOP VIEW AA2 A1 bbb Z DETAIL A A3 A2 bFRONT VIEW SIDE VIEW DETAIL A ROTATED 90 BUMP eee Z b (25x) ccc Z YXddd ZMMA1 DS12232 Rev 5 113/143 

STM32G071x8/xB Package information 

> 135

Figure 35. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip scale recommended footprint 

1. Dimensions are expressed in millimeters. e - 0.40 - - 0.016 -e1 - 1.60 - - 0.063 -e2 - 1.60 - - 0.063 -F(4) - 0.350 - - 0.014 -G(4) - 0.440 - - 0.017 -aaa - - 0.10 - - 0.004 bbb - - 0.10 - - 0.004 ccc - - 0.10 - - 0.004 ddd - - 0.05 - - 0.002 eee - - 0.05 - - 0.002 1. Values in inches are converted from mm and rounded to 3 decimal digits. 2. The maximum total package height is calculated by the RSS method (Root Sum Square) using nominal and tolerances values of A1 and A2. 3. Back side coating. Nominal dimension is rounded to the 3rd decimal place resulting from process capability. 4. Calculated dimensions are rounded to the 3rd decimal place 

Table 77. WLCSP25 recommended PCB design rules Dimension Recommended values 

Pitch 0.4 mm Dpad 0,225 mm Dsm 0.290 mm typ. (depends on soldermask registration tolerance) 

Table 76. WLCSP - 25 balls, 2.30x2.48 mm, 0.4 mm pitch, wafer level chip scale mechanical data (continued) Symbol millimeters inches (1) Min Typ Max Min Typ Max 

> A06J_WLCSP25_FP_V2

Dpad Dsm Package information STM32G071x8/xB 

114/143 DS12232 Rev 5 

Device marking 

The following figure gives an example of topside marking orientation versus ball A1 identifier location. The printed markings may differ depending on the supply chain. Other optional marking or inset/upset marks that identify the parts throughout supply chain operations, are not indicated below. 

Figure 36. WLCSP25 package marking example 

Stencil opening 0.250 mm Stencil thickness 0.100 mm 

Table 77. WLCSP25 recommended PCB design rules Dimension Recommended values 

> MSv47937V3 Product identification Date code Revision code

# G0786 RY WW 

> Ball A1 identifier

DS12232 Rev 5 115/143 

STM32G071x8/xB Package information 

> 135

# 6.3 UFQFPN28 package information (A0B0) 

UFQFPN28 is a 28-lead, 4 x 4 mm, 0.5 mm pitch, ultra thin fine pitch quad flat package. 

Figure 37. UFQFPN28 - Outline  

> 1. Drawing is not to scale.

Table 78. UFQFPN28 – Mechanical data (1)  

> 1. Values in inches are converted from mm and rounded to 4 decimal digits.

Symbol millimeters inches Min Typ Max Min Typ Max 

A 0.500 0.550 0.600 0.0197 0.0217 0.0236 A1 - 0.000 0.050 - 0.0000 0.0020 D 3.900 4.000 4.100 0.1535 0.1575 0.1614 D1 2.900 3.000 3.100 0.1142 0.1181 0.1220 E 3.900 4.000 4.100 0.1535 0.1575 0.1614 E1 2.900 3.000 3.100 0.1142 0.1181 0.1220 L 0.300 0.400 0.500 0.0118 0.0157 0.0197 L1 0.250 0.350 0.450 0.0098 0.0138 0.0177 T - 0.152 - - 0.0060 -b 0.200 0.250 0.300 0.0079 0.0098 0.0118 e - 0.500 - - 0.0197 -

> A0B0_ME_V5 D1 E1 DE

Detail Z Detail Y DPackage information STM32G071x8/xB 

116/143 DS12232 Rev 5 

Figure 38. UFQFPN28 – Footprint example 

1. Dimensions are expressed in millimeters. 

3.30 0.50 0.21 3.20 3.20 3.30 4.30 0.30 0.20 0.21 0.50 0.50 3.30 0.55 A0B0_FP_V3 DS12232 Rev 5 117/143 

STM32G071x8/xB Package information 

135 

# 6.4 LQFP32 package information (5V) 

This LQFP is a 32-pin, 7 x 7 mm, low-profile quad flat package. 

Note:  Figure  39  is not to scale. 

Refer to the notes section for the list of notes on  Figure  39  and  Table  79 .

Figure 39. LQFP32 - Outline 

SECTION A-A GAUGE PLANE BBSECTION B-B HLSR1 R2 SECTION B-B bb1 c c1 WITH PLATING BASE METAL 

1

3

2

(3) E1 5V_LQFP32_ME_V1 BOTTOM VIEW TOP VIEW (6) aaa C A-B D 4x N/4 TIPS bbb H A-B D 4x D 1/4 E 1/4 ddd C A-B D N(12) A2 (13) (N – 4)x e 0.05 ccc C A1 AbCD 1/4 (3) (4) A123(10) (2) (5) D1 DD (3) (4) (2) (5) E(6) AA(Section A-A) BE 1/4 E 1/4 (L1) (2) 0.25 (11) (9) (11) (11) (11) (11) (1) Package information STM32G071x8/xB 

118/143 DS12232 Rev 5 

Table 79. LQFP32 - Mechanical data Symbol millimeters inches (14) Min Typ Max Min Typ Max 

θ 0° 3.5° 7° 0° 3.5° 7° 

θ1 0° - - 0° - -

θ2 10° 12° 14° 10° 12° 14° 

θ3 10° 12° 14° 10° 12° 14° A - - 1.60 - - 0.0630 A1 (12) 0.05 - 0.15 0.0020 - 0.0059 A2 1.35 1.40 1.45 0.0531 0.0551 0.0571 b(9)(11) 0.30 0.37 0.45 0.0118 0.0146 0.0177 b1 (11) 0.30 0.35 0.40 0.0118 0.0128 0.0157 c(11) 0.09 - 0.20 0.0035 - 0.0079 c1 (11) 0.09 - 0.16 0.0035 - 0.0063 D(4) 9.00 BSC 0.3543 BSC D1 (2)(5) 7.00 BSC 0.2756 BSC e 0.80 BSC 0.0315 BSC E(4) 9.00 BSC 0.3543 BSC E1 (2)(5) 7.00 BSC 0.2756 BSC L 0.45 0.60 0.75 0.0177 0.0236 0.0295 L1 1.00 REF 0.0394 REF N(13) 32 R1 0.08 - - 0.0031 - -R2 0.08 - 0.20 0.0031 - 0.0079 S 0.20 - - 0.0079 - -aaa (1)(7)(15) 0.20 0.0079 bbb (1)(7)(15) 0.20 0.0079 ccc (1)(7)(15) 0.10 0.0039 ddd (1)(7)(15) 0.20 0.0079 DS12232 Rev 5 119/143 

STM32G071x8/xB Package information 

> 135

Notes: 

1. Dimensioning and tolerancing schemes conform to ASME Y14.5M-1994. 

2. The top package body size may be smaller than the bottom package size by as much as 0.15 mm. 

3. Datums A-B and D to be determined at datum plane H. 

4. To be determined at the seating datum plane C. 

5. Dimensions D1 and E1 do not include mold flash or protrusions. Allowable mold flash or protrusions is “0.25 mm” per side. D1 and E1 are maximum plastic body size dimensions including mold mismatch. 

6. Details of pin 1 identifier are optional but must be located within the zone indicated. 

7. All dimensions are in millimeters. 

8. No intrusion is allowed inwards the leads. 

9. Dimension b does not include a dambar protrusion. Allowable dambar protrusion shall not cause the lead width to exceed the maximum “b” dimension by more than 0.08 mm. Dambar cannot be located on the lower radius or the foot. The minimum space between the protrusion and an adjacent lead is 0.07 mm for 0.4 mm and 0.5 mm pitch packages. 

10. The exact shape of each corner is optional. 

11. These dimensions apply to the flat section of the lead between 0.10 mm and 0.25 mm from the lead tip. 

12. A1 is defined as the distance from the seating plane to the lowest point on the package body. 

13. N is the number of terminal positions for the specified body size. 

14. Values in inches are converted from mm and rounded to four decimal digits. 

15. Recommended values and tolerances. Package information STM32G071x8/xB 

120/143 DS12232 Rev 5 

Figure 40. LQFP32 – Footprint example 

1. Dimensions are expressed in millimeters. 

> 5V_LQFP32_FP_V4 7.4 9.8

7.4 9.8 0.8 0.45 1.2 REF Soldering area Solder resist opening 32 25 81 24 17 9 16 DS12232 Rev 5 121/143 

STM32G071x8/xB Package information 

135 

# 6.5 UFQFPN32 package information (A0B8) 

This UFQFPN is a 32-pin, 5 x 5 mm, 0.5 mm pitch ultra thin fine pitch quad flat package. 

Note: Figure  41 and Figure  42 are not to scale. 

Refer to the notes section for the list of notes on  Figure  41 , Table  80 , and  Table  81 .

Figure 41. UFQFPN32 - Outline 

> A0B8_UFQFPN32_ME_V6

TOP VIEW FRONT VIEW BOTTOM VIEW bbb C A B ddd Cfff C A B fff C A B aaa CSection A-A (See section A-A) Detail C (See detail C) ccc CA ATerminal A1 Index area X4 ED A BCA3 9A1 9E2 14 2xR bL 15 Seating plane Terminal 1 indicator D2 eC32 21KA Seating plane eCeee CPackage information STM32G071x8/xB 

122/143 DS12232 Rev 5 

Table 80. UFQFPN32 - Mechanical data Symbol Millimeters Inches (23) Min Typ Max Min Typ Max 

A(17)(18) 0.50 0.55 0.60 0.0197 0.0217 0.0236 A1 (19) 0.00 - 0.05 0.000 - 0.0020 b(21)(30) 0.18 0.25 0.30 0.0071 0.0098 0.0118 D(22) 5.00 BSC 0.1969 BSC D2 3.40 3.50 3.60 0.1339 0.1378 0.1417 E(22) 5.00 BSC 0.1969 BSC E2 3.40 3.50 3.60 0.1339 0.1378 0.1417 e 0.50 BSC 0.0197 BSC N(27) 32 L(30) 0.30 - 0.50 0.0118 - 0.0197 R 0.09 - - 0.0035 - -

Table 81. Tolerance of form and position Symbol Millimeters Inches (23) 

aaa 0.15 0.0059 bbb 0.10 0.0039 ccc 0.10 0.0039 ddd 0.05 0.0020 eee 0.08 0.0315 fff 0.10 0.0039 DS12232 Rev 5 123/143 

STM32G071x8/xB Package information 

> 135

Notes: 

16. Dimensioning and tolerancing schemes conform to ASME Y14.5M-2018 except for European. 

17. UFQFPN stands for ultra-thin fine pitch quad flat package no lead: A ≤ 0.60 mm / Fine pitch e ≤ 1.00 mm. 

18. The profile height, A, is the distance from the seating plane to the highest point on the package. It is measured perpendicular to the seating plane. 

19. A1 is the vertical distance from the bottom surface of the plastic body to the nearest metallized package feature. 

20. A3 is the distance from the seating plane to the upper surface of the terminals. 

21. Dimension b applies to metallized terminal. If the terminal has the optional radius on the other end of the terminal, the dimension b should not be measured in that radius area. 

22. BSC stands for BASIC dimensions. It corresponds to the nominal value and has no tolerance. 

23. Values in inches are converted from millimeters and rounded to four decimal digits. 

24. Primary datum C is defined by the plane established by the contact points of three or more solder balls that support the device when it is placed on top of a planar surface. 

25. Terminal A1 identifier and terminal numbering convention must conform to JEP95 SPP-002. Terminal A1 identifier must be located within the zone indicated on the outline drawing. Topside terminal A1 indicator may be a molded, or metallized feature. Optional indicator on bottom surface may be a molded, marked, or metallized feature. 

26. ddd coplanarity zone applies to the exposed pad as well as the terminals. 

27. N represents the total number of terminals. 

28. K gives the minimum separation between any two terminals or the terminals and the edges of the exposed metal heat feature. 

29. The inner edge of corner terminals may be chamfered or rounded to achieve minimum gap k. This feature should not affect the terminal width b, which is measured L/2 from the edge of the package body. 

30. Dimension b and L are measured at the terminal planting surface. Package information STM32G071x8/xB 

124/143 DS12232 Rev 5 

Figure 42. UFQFPN32 - Footprint example 

1. Dimensions are expressed in millimeters. 

> A0B8_EP-3.5x3.5mm_UFQFPN32_FP_V1

5.50 3.75 0.65 3.50 0.50 3.50 3.75 3.75 0.25 5.50 189 16 17 24 25 32 DS12232 Rev 5 125/143 

STM32G071x8/xB Package information 

135 

# 6.6 LQFP48 package information (5B) 

This LQFP is a 48-pin, 7 x 7 mm low-profile quad flat package. 

Note: See list of notes in the notes section. 

Figure 43. LQFP48 - Outline (15) 

SECTION A-A GAUGE PLANE BBSECTION B-B HLSR1 R2 SECTION B-B bb1 c c1 WITH PLATING BASE METAL 

1

3

2

5B_LQFP48_ME_V1 (6) aaa C A-B D 4x N/4 TIPS bbb H A-B D 4x ddd C A-B D (12) (13) (N – 4)x e ccc C AD 1/4 E 1/4 0.05 A1 A2 bC(3) E1 D 1/4 (3) (4) A123(2) (5) D1 DD (3) (4) E(Section A-A) BE 1/4 N(10) (5) (2) (6) AABOTTOM VIEW TOP VIEW (L1) (2) 0.25 (11) (9) (11) (11) (11) (11) (1) Package information STM32G071x8/xB 

126/143 DS12232 Rev 5 

Table 82. LQFP48 - Mechanical data Symbol millimeters inches (14) Min Typ Max Min Typ Max 

A - - 1.60 - - 0.0630 A1 (12) 0.05 - 0.15 0.0020 - 0.0059 A2 1.35 1.40 1.45 0.0531 0.0551 0.0571 b(9)(11) 0.17 0.22 0.27 0.0067 0.0087 0.0106 b1 (11) 0.17 0.20 0.23 0.0067 0.0079 0.0090 c(11) 0.09 - 0.20 0.0035 - 0.0079 c1 (11) 0.09 - 0.16 0.0035 - 0.0063 D(4) 9.00 BSC 0.3543 BSC D1 (2)(5) 7.00 BSC 0.2756 BSC E(4) 9.00 BSC 0.3543 BSC E1 (2)(5) 7.00 BSC 0.2756 BSC e 0.50 BSC 0.1970 BSC L 0.45 0.60 0.75 0.0177 0.0236 0.0295 L1 1.00 REF 0.0394 REF N(13) 48 

θ 0° 3.5° 7° 0° 3.5° 7° 

θ1 0° - - 0° - -

θ2 10° 12° 14° 10° 12° 14° 

θ3 10° 12° 14° 10° 12° 14° R1 0.08 - - 0.0031 - -R2 0.08 - 0.20 0.0031 - 0.0079 S 0.20 - - 0.0079 - -aaa (1)(7) 0.20 0.0079 bbb (1)(7) 0.20 0.0079 ccc (1)(7) 0.08 0.0031 ddd (1)(7) 0.08 0.0031 DS12232 Rev 5 127/143 

STM32G071x8/xB Package information 

> 135

Notes: 

1. Dimensioning and tolerancing schemes conform to ASME Y14.5M-1994. 

2. The Top package body size may be smaller than the bottom package size by as much as 0.15 mm. 

3. Datums A-B and D to be determined at datum plane H. 

4. To be determined at seating datum plane C. 

5. Dimensions D1 and E1 do not include mold flash or protrusions. Allowable mold flash or protrusions is “0.25 mm” per side. D1 and E1 are Maximum plastic body size dimensions including mold mismatch. 

6. Details of pin 1 identifier are optional but must be located within the zone indicated. 

7. All Dimensions are in millimeters. 

8. No intrusion allowed inwards the leads. 

9. Dimension “b” does not include dambar protrusion. Allowable dambar protrusion shall not cause the lead width to exceed the maximum “b” dimension by more than 0.08 mm. Dambar cannot be located on the lower radius or the foot. Minimum space between protrusion and an adjacent lead is 0.07 mm for 0.4 mm and 0.5 mm pitch packages. 

10. Exact shape of each corner is optional. 

11. These dimensions apply to the flat section of the lead between 0.10 mm and 0.25 mm from the lead tip. 

12. A1 is defined as the distance from the seating plane to the lowest point on the package body. 

13. “N” is the number of terminal positions for the specified body size. 

14. Values in inches are converted from mm and rounded to 4 decimal digits. 

15. Drawing is not to scale. 

Figure 44. LQFP48 - Footprint example   

> 1. Dimensions are expressed in millimeters.
> 12 24 137 36 5.80 0.30 25 1.20 0.50 13 48 9.70 7.30 9.70 0.20 5B_LQFP48_FP_V1

Package information STM32G071x8/xB 

128/143 DS12232 Rev 5 

# 6.7 UFQFPN48 package information (A0B9) 

This UFQFPN is a 48-lead, 7 x 7 mm, 0.5 mm pitch, ultra thin fine pitch quad flat package. 

Figure 45. UFQFPN48 – Outline 

1. Drawing is not to scale. 2. All leads/pads should also be soldered to the PCB to improve the lead/pad solder joint life. 3. There is an exposed die pad on the underside of the UFQFPN48 package. It is recommended to connect and solder this back-side pad to PCB ground. 

D1 E1 EXPOSED PAD E2 eD2 PIN 1 idenfier BOTTOM VIEW LAA3 CFRONT VIEW DETAIL A SEATING PLANE LEADS COPLANARITY Cddd SEATING PLANE A1 A1 ACCddd PIN 1 IDENTIFIER LASER MAKER AREA EDTOP VIEW A0B9_UFQFPN48_ME_V4 DS12232 Rev 5 129/143 

STM32G071x8/xB Package information 

> 135

Figure 46. UFQFPN48 – Footprint example 

1. Dimensions are expressed in millimeters. 

Table 83. UFQFPN48 – Mechanical data Symbol millimeters inches (1) 

1. Values in inches are converted from mm and rounded to four decimal digits. 

Min Typ Max Min Typ Max 

A 0.500 0.550 0.600 0.0197 0.0217 0.0236 A1 0.000 0.020 0.050 0.0000 0.0008 0.0020 A3 - 0.152 - - 0.0060 -b 0.200 0.250 0.300 0.0079 0.0098 0.0118 D(2) 2. Dimensions D and E do not include mold protrusion, not exceed 0.15 mm. 6.900 7.000 7.100 0.2717 0.2756 0.2795 D1 5.400 5.500 5.600 0.2126 0.2165 0.2205 D2 (3) 3. Dimensions D2 and E2 are not in accordance with JEDEC. 5.500 5.600 5.700 0.2165 0.2205 0.2244 E(2) 6.900 7.000 7.100 0.2717 0.2756 0.2795 E1 5.400 5.500 5.600 0.2126 0.2165 0.2205 E2 (3) 5.500 5.600 5.700 0.2165 0.2205 0.2244 e - 0.500 - - 0.0197 -L 0.300 0.400 0.500 0.0118 0.0157 0.0197 ddd - - 0.080 - - 0.0031   

> 7.30 7.30 0.20 0.30 0.55 0.50 5.80 6.20 6.20 5.60 5.60 5.80 0.75 A0B9_UFQFPN48_FP_V3 48 112 13 24 25 36 37

Package information STM32G071x8/xB 

130/143 DS12232 Rev 5 

# 6.8 LQFP64 package information (5W) 

This LQFP is 64-pin, 10 x 10 mm low-profile quad flat package. 

Note: See list of notes in the notes section. 

Figure 47. LQFP64 - Outline (15) 

D 1/4 E 1/4 (6) aaa C A-B D 4x N/4 TIPS bbb H A-B D 4x (13) (N – 4)x e 0.05 AA2 A1 (12) b ddd C A-B D ccc CCD(5) (2) (4) D1 D (3) D 1/4 E 1/4 (6) 123(3) A B (3) (5) (2) E1 EAA(Section A-A) (4) 5W_LQFP64_ME_V1 (10) NBOTTOM VIEW TOP VIEW SECTION A-A GAUGE PLANE BBSECTION B-B HLSR1 R2 SECTION B-B bb1 c c1 WITH PLATING BASE METAL 

1

3

2

(L1) (2) 0.25 (11) (9) (11) (11) (11) (11) (1) DS12232 Rev 5 131/143 

STM32G071x8/xB Package information 

> 135

Table 84. LQFP64 - Mechanical data Symbol millimeters inches (14) Min Typ Max Min Typ Max 

A - - 1.60 - - 0.0630 A1 (12) 0.05 - 0.15 0.0020 - 0.0059 A2 1.35 1.40 1.45 0.0531 0.0551 0.0570 b(9)(11) 0.17 0.22 0.27 0.0067 0.0087 0.0106 b1 (11) 0.17 0.20 0.23 0.0067 0.0079 0.0091 c(11) 0.09 - 0.20 0.0035 - 0.0079 c1 (11) 0.09 - 0.16 0.0035 - 0.0063 D(4) 12.00 BSC 0.4724 BSC D1 (2)(5) 10.00 BSC 0.3937 BSC E(4) 12.00 BSC 0.4724 BSC E1 (2)(5) 10.00 BSC 0.3937 BSC e 0.50 BSC 0.1970 BSC L 0.45 0.60 0.75 0.0177 0.0236 0.0295 L1 1.00 REF 0.0394 REF N(13) 64 

θ 0° 3.5° 7° 0° 3.5° 7° 

θ1 0° - - 0° - -

θ2 10° 12° 14° 10° 12° 14° 

θ3 10° 12° 14° 10° 12° 14° R1 0.08 - - 0.0031 - -R2 0.08 - 0.20 0.0031 - 0.0079 S 0.20 - - 0.0079 - -aaa (1) 0.20 0.0079 bbb (1) 0.20 0.0079 ccc (1) 0.08 0.0031 ddd (1) 0.08 0.0031 Package information STM32G071x8/xB  

> 132/143 DS12232 Rev 5

Notes: 

1. Dimensioning and tolerancing schemes conform to ASME Y14.5M-1994. 

2. The Top package body size may be smaller than the bottom package size by as much as 0.15 mm. 

3. Datums A-B and D to be determined at datum plane H. 

4. To be determined at seating datum plane C. 

5. Dimensions D1 and E1 do not include mold flash or protrusions. Allowable mold flash or protrusions is “0.25 mm” per side. D1 and E1 are Maximum plastic body size dimensions including mold mismatch. 

6. Details of pin 1 identifier are optional but must be located within the zone indicated. 

7. All Dimensions are in millimeters. 

8. No intrusion allowed inwards the leads. 

9. Dimension “b” does not include dambar protrusion. Allowable dambar protrusion shall not cause the lead width to exceed the maximum “b” dimension by more than 0.08 mm. Dambar cannot be located on the lower radius or the foot. Minimum space between protrusion and an adjacent lead is 0.07 mm for 0.4 mm and 0.5 mm pitch packages. 

10. Exact shape of each corner is optional. 

11. These dimensions apply to the flat section of the lead between 0.10 mm and 0.25 mm from the lead tip. 

12. A1 is defined as the distance from the seating plane to the lowest point on the package body. 

13. “N” is the number of terminal positions for the specified body size. 

14. Values in inches are converted from mm and rounded to 4 decimal digits. 

15. Drawing is not to scale. 

Figure 48. LQFP64 - Footprint example     

> 1. Dimensions are expressed in millimeters.
> 48 32 49 64 17 116 1.20 0.30 33 10.30 12.70 10.30 0.5 7.80 12.70 5W_LQFP64_FP_V2

DS12232 Rev 5 133/143 

STM32G071x8/xB Package information 

135 

# 6.9 UFBGA64 package information (A019) 

This UFBGA is a 64-ball, 5 x 5 mm, 0.5 mm pitch ultra profile fine pitch ball grid array package. 

Note: See list of notes in the notes section. 

Figure 49. UFBGA64 – Outline (13) 

> A019_UFBGA64_ME_V2 Seating plane

e SE eDHØb (N balls) AETOP VIEW SIDE VIEW 81SD ACB Aaaa C D1 E1 A1 A1 ball pad corner (9) A2 FBGECD2 3 4 65 7Detail A eee C A Bfff ØØMM C A1 ball pad corner (DATUM A) (DATUM B) (4X) ddd ccc CCDetail A Solder balls Mold resin Substrate (8) Package information STM32G071x8/xB  

> 134/143 DS12232 Rev 5

Notes: 

1. Dimensioning and tolerancing schemes conform to ASME Y14.5M-2009 apart European projection. 

2. UFBGA stands for ultra profile fine pitch ball grid array: 0.5 mm < A ≤ 0.65 mm / fine pitch e < 1.00 mm. 

3. The profile height, A, is the distance from the seating plane to the highest point on the package. It is measured perpendicular to the seating plane. 

4. A1 is defined as the distance from the seating plane to the lowest point on the package body. 

5. Dimension b is measured at the maximum diameter of the terminal (ball) in a plane parallel to primary datum C. 

6. BSC stands for BASIC dimensions. It corresponds to the nominal value and has no tolerance. For tolerances refer to form and position table. On the drawing these dimensions are framed. 

7. Primary datum C is defined by the plane established by the contact points of three or more solder balls that support the device when it is placed on top of a planar surface. 

8. The terminal (ball) A1 corner must be identified on the top surface of the package by using a corner chamfer, ink or metalized markings, or other feature of package body or 

Table 85. UFBGA64 – Mechanical data Symbol millimeters (1) inches (12) Min Typ Max Min Typ Max                                                   

> A(2)(3) --0.60 --0.0236 A1 (4) 0.05 --0.0020 --A2 -0.43 --0.0169 -b(5) 0.23 0.28 0.33 0.0090 0.0110 0.0130 D(6) 5.00 BSC 0.1969 BSC D1 3.50 BSC 0.1378 BSC E5.00 BSC 0.1969 BSC E1 3.50 BSC 0.1378 BSC e(9) 0.50 BSC 0.0197 BSC N(11) 64 SD (12) 0.25 BSC 0.0098 BSC SE (12) 0.25 BSC 0.0098 BSC aaa 0.15 0.0059 ccc 0.20 0.0079 ddd 0.08 0.0031 eee 0.15 0.0059 fff 0.05 0.0020 DS12232 Rev 5 135/143

STM32G071x8/xB Package information 

> 135

integral heat slug. A distinguish feature is allowable on the bottom surface of the package to identify the terminal A1 corner. Exact shape of each corner is optional. 

9. e represents the solder ball grid pitch. 

10. N represents the total number of balls on the BGA. 

11. Basic dimensions SD and SE are defined with respect to datums A and B. It defines the position of the centre ball(s) in the outer row or column of a fully populated matrix. 

12. Values in inches are converted from mm and rounded to 4 decimal digits. 

13. Drawing is not to scale. 

Figure 50. UFBGA64 – Footprint example 

Table 86. UFBGA64 - Example of PCB design rules (0.5 mm pitch BGA) Dimension Values       

> Pitch 0.5 mm Dpad 0.280 mm Dsm 0.370 mm typ. (depends on the soldermask registration tolerance) Stencil opening 0.280 mm Stencil thickness Between 0.100 mm and 0.125 mm Pad trace width 0.100 mm
> BGA_WLCSP_FT_V1

Dsm Dpad STM32G071x8/xB 

136/143 DS12232 Rev 5 

# 6.10 Thermal characteristics 

The operating junction temperature T J must never exceed the maximum given in The maximum junction temperature in °C that the device can reach if respecting the operating conditions, is: TJ(max) = T A(max) + P D(max) x ΘJA where: 

• TA(max) is the maximum operating ambient temperature in °C, 

• ΘJA is the package junction-to-ambient thermal resistance, in °C/W, 

• PD = P INT + P I/O ,– PINT is power dissipation contribution from product of I DD and V DD – PI/O is power dissipation contribution from output ports where: PI/O = Σ (V OL × I OL ) + Σ ((V DDIO1 – V OH ) × I OH ), taking into account the actual V OL / I OL and V OH / I OH of the I/Os at low and high level in the application. 

Table 21: General operating conditions .

Table 87. Package thermal characteristics Symbol Parameter Package Value Unit 

ΘJA Thermal resistance junction-ambient WLCSP25 75 °C/W UFQFPN28 69 LQFP32 63 UFQFPN32 41 LQFP48 64 UFQFPN48 31 LQFP64 55 UFBGA64 82 

ΘJB Thermal resistance junction-board WLCSP25 44 °C/W UFQFPN28 39 LQFP32 31 UFQFPN32 23 LQFP48 31 UFQFPN48 15 LQFP64 28 UFBGA64 53 DS12232 Rev 5 137/143 

STM32G071x8/xB 

> 138

## 6.10.1 Reference document 

JESD51-2 Integrated Circuits Thermal Test Method Environment Conditions - Natural Convection (still air). Available from www.jedec.org. 

## 6.10.2 Selecting the product temperature range 

The temperature range is specified in the ordering information scheme shown in Section 7: Ordering information .Each temperature range suffix corresponds to a specific guaranteed ambient temperature at maximum dissipation and to a specific maximum junction temperature. As applications do not commonly use microcontrollers at their maximum power consumption, it is useful to calculate the exact power consumption and junction temperature to determine which temperature range best suits the application. The following example shows how to calculate the temperature range needed for a given application. 

Example: 

Assuming the following worst application conditions: 

• ambient temperature TA = 50 °C (measured according to JESD51-2) 

• IDD = 50 mA; VDD = 3.6 V 

• 20 I/Os simultaneously used as output at low level with IOL = 8 mA (VOL= 0.4 V), and 

• 8 I/Os simultaneously used as output at low level with IOL = 20 mA (VOL= 1.3 V), the power consumption from power supply PINT is: PINT = 50 mA × 3.6 V= 118 mW, the power loss through I/Os PIO is PIO = 20 × 8 mA × 0.4 V + 8 × 20 mA × 1.3 V = 272 mW, and the total power P D to dissipate is: PD = 180 mW + 272 mW = 452 mW For a package with ΘJA = 65 °C/W, the junction temperature stabilizes at: TJ = 50°C + (65 °C/W × 452 mW) = 50 °C + 29.4 °C = 79.4 °C 

ΘJC Thermal resistance junction-board WLCSP25 5°C/W UFQFPN28 21 LQFP32 15 UFQFPN32 21 LQFP48 15 UFQFPN48 12 LQFP64 13 UFBGA64 21 

Table 87. Package thermal characteristics (continued) Symbol Parameter Package Value Unit STM32G071x8/xB  

> 138/143 DS12232 Rev 5

As a conclusion, product version with suffix 6 (maximum allowed TJ = 105° C) is sufficient for this application. If the same application was used in a hot environment with maximum T A greater than 75.5 °C, the junction temperature would exceed 105°C and the product version allowing higher maximum T J would have to be ordered. DS12232 Rev 5 139/143 

STM32G071x8/xB Ordering information 

> 139

# 7 Ordering information 

For a list of available options (memory, package, and so on) or for further information on any aspect of this device, contact your nearest ST sales office. Example STM32 G 071 K 8 T 6 xyy 

Device family 

STM32 = Arm ® based 32-bit microcontroller 

Product type 

G = general-purpose 

Device subfamily 

071 = STM32G071 

Pin count 

E = 25 G = 28 K = 32 C = 48 R = 64 

Flash memory size 

8 = 64 Kbytes B = 128 Kbytes 

Package type 

I = UFBGA T = LQFP U = UFQFPN Y = WLCSP 

Temperature range 

6 = -40 to 85°C (105°C junction) 7 = -40 to 105°C (125°C junction) 3 = -40 to 125°C (130°C junction) 

Options 

xTR = tape and reel packing; x = N (“N” product version), otherwise blank x˽˽ = tray packing; x = N (“N” product version) or blank other = 3-character ID incl. custom Flash code and packing information; x = N for “N” product version Important security notice STM32G071x8/xB  

> 140/143 DS12232 Rev 5

# 8 Important security notice 

The STMicroelectronics group of companies (ST) places a high value on product security, which is why the ST product(s) identified in this documentation may be certified by various security certification bodies and/or may implement our own security measures as set forth herein. However, no level of security certification and/or built-in security measures can guarantee that ST products are resistant to all forms of attacks. As such, it is the responsibility of each of ST's customers to determine if the level of security provided in an ST product meets the customer needs both in relation to the ST product alone, as well as when combined with other components and/or software for the customer end product or application. In particular, take note that: 

• ST products may have been certified by one or more security certification bodies, such as Platform Security Architecture (www.psacertified.org) and/or Security Evaluation standard for IoT Platforms (www.trustcb.com). For details concerning whether the ST product(s) referenced herein have received security certification along with the level and current status of such certification, either visit the relevant certification standards website or go to the relevant product page on www.st.com for the most up to date information. As the status and/or level of security certification for an ST product can change from time to time, customers should re-check security certification status/level as needed. If an ST product is not shown to be certified under a particular security standard, customers should not assume it is certified. 

• Certification bodies have the right to evaluate, grant and revoke security certification in relation to ST products. These certification bodies are therefore independently responsible for granting or revoking security certification for an ST product, and ST does not take any responsibility for mistakes, evaluations, assessments, testing, or other activity carried out by the certification body with respect to any ST product. 

• Industry-based cryptographic algorithms (such as AES, DES, or MD5) and other open standard technologies which may be used in conjunction with an ST product are based on standards which were not developed by ST. ST does not take responsibility for any flaws in such cryptographic algorithms or open technologies or for any methods which have been or may be developed to bypass, decrypt or crack such algorithms or technologies. 

• While robust security testing may be done, no level of certification can absolutely guarantee protections against all attacks, including, for example, against advanced attacks which have not been tested for, against new or unidentified forms of attack, or against any form of attack when using an ST product outside of its specification or intended use, or in conjunction with other components or software which are used by customer to create their end product or application. ST is not responsible for resistance against such attacks. As such, regardless of the incorporated security features and/or any information or support that may be provided by ST, each customer is solely responsible for determining if the level of attacks tested for meets their needs, both in relation to the ST product alone and when incorporated into a customer end product or application. 

• All security features of ST products (inclusive of any hardware, software, documentation, and the like), including but not limited to any enhanced security features added by ST, are provided on an "AS IS" BASIS. AS SUCH, TO THE EXTENT PERMITTED BY APPLICABLE LAW, ST DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, unless the applicable written and signed contract terms specifically provide otherwise. DS12232 Rev 5 141/143 

STM32G071x8/xB Revision history 

> 142

# 9 Revision history 

Table 88. Document revision history Date Revision Changes 

8-Nov-2018 1 Initial release. 28-Nov-2018 2

Table 19 : IINJ(PIN) parameter definition modified; 

Table 21 : V IN parameter definition modified; 

Table 51 : FT_d type added to I lkg parameter specification, note attached to I lkg values, and TT_xx modified to TT_a; 

Table 58 : “single ended mode” removed from I DDV(ADC) parameter definition; 

Table 87 : UFBGA64 5x5 mm package ΘJA corrected 06-Mar-2020 3Cover page updated; 

Section 2: Description updated; 

Section 3.3.1: Securable area added; 

Section 3.7.1: Power supply schemes : corrected minimum VDD and VDDA values; 

Section 3.14.1: Temperature sensor : “engineering bytes” replaced “System memory”; 

Section 3.20: Inter-integrated circuit interface (I 2C) : SMBus and PMBus feature points; 

Section 3.21: Universal synchronous/asynchronous receiver transmitter (USART) : max. speed corrected; 

Table 12 : Note 3 inserted and note 4 modified; 

Table 18 updated; 

Table 19 : Note 2 removed; 

Table 21 : Redefined V IN for I/Os of other than TT_xx and FT_c type; 

Table 49 : LU class modified from “II” to “II Level A”; 

Table 52 : I/O current condition for relaxed VOL/VOH corrected from 18 mA to 15 mA; section Output driving current corrected accordingly; 

Table 58 : major update; 

Section 3.12: DMA request multiplexer (DMAMUX) added; Figures with package marking examples corrected. 23-Sep-2021 4Updated: – Section 2: Description 

– Section 4: Pinouts, pin description and alternate functions 

– Replaced “PD version” reference for “N version” reference on Figure 6: STM32G071KxU UFQFPN32 pinout , Figure 4: STM32G071GxU UFQFPN28 pinout , Table 12: Pin assignment and description and Section 7: Ordering information 

– Section 6: Package information : all subsections were rearranged – Example in Section 6.10.2: Selecting the product temperature range 

– Footnote 3 on Table 25: Current consumption in Run and Low-power run modes at different die temperatures 

– Footnote 2 on Table 43: PLL characteristics 

– VIL line on Table 51: I/O static characteristics 

– VREFBUF_OUT line on Table 63: VREFBUF characteristics Revision history STM32G071x8/xB 

142/143 DS12232 Rev 5 

17-Jun-2025 5Cover page updated; Added references to the reference manual and errata sheet into Section 1: Introduction ;Added information on standard and alternative pinouts in Section 2: Description 

preamble; Updated Table 2: STM32G071x8/xB device features and peripheral counts ;Updated Table 3: Access status versus readout protection level and execution modes (OTP added); Updated Section 3.5: Boot modes ;Updated Section 3.7.6: VBAT operation ;Updated Section 3.14: Analog-to-digital converter (ADC) ;Updated Table 7: Timer feature comparison ;Updated Section 3.21: Universal synchronous/asynchronous receiver transmitter (USART) ;Updated Section 4: Pinouts, pin description and alternate functions (packages ordered from lowest to highest pin count), with Table 11: Terms and symbols used in Pin assignment and description table ;Updated Figure 13: Power supply scheme ;Updated Section 5.2: Absolute maximum ratings , with Table 18: Voltage characteristics and Table 19: Current characteristics ;In Section 5.3: Operating conditions , all table footnotes “Guaranteed by design” changed to “Specified by design. Not tested in production”, updated Table 21: General operating conditions , Section : I/O system current consumption ,

Table 47: EMI characteristics , Section : General input/output characteristics (a note added), Table 52: Output voltage characteristics , title change for Section : Output buffer timing characteristics and Table 53: Non-FT_c I/O output timing characteristics , Figure 22: I/O AC characteristics definition , Figure 23: Recommended NRST pin protection , Section : Output driving current and 

Table 52: Output voltage characteristics (maximum driving current), added 

Section 5.3.16: Extended interrupt and event controller input (EXTI) characteristics , updated Table 58: ADC characteristics , Table 60: ADC accuracy ,

Figure 24: ADC accuracy characteristics , Figure 25: ADC typical connection diagram , Table 63: VREFBUF characteristics , Table 64: COMP characteristics 

(removed IDDA(COMP) medium-speed mode and deglitcher information), 

Figure 27: SPI timing diagram - slave mode and CPHA = 0 , Figure 28: SPI timing diagram - slave mode and CPHA = 1 , title of Section : USART (SPI mode) characteristics and Table 74: USART characteristics in SPI mode , added 

Figure 32: USART timing diagram in SPI master mode and Figure 33: USART timing diagram in SPI slave mode , updated Table 75: UCPD operating conditions ;Updated Section 6: Package information , with added Section 6.1: Device marking , removed corresponding subsections for all packages except for WLCSP25, and added note related to Section 6.5: UFQFPN32 package information (A0B8) ;Updated Table 87: Package thermal characteristics ;Added Section 8: Important security notice .

Table 88. Document revision history (continued) Date Revision Changes DS12232 Rev 5 143/143 

STM32G071x8/xB 

> 143

IMPORTANT NOTICE – READ CAREFULLY 

STMicroelectronics NV and its subsidiaries (“ST”) reserve the right to make changes, corrections, enhancements, modifications, and improvements to ST products and/or to this document at any time without notice. Purchasers should obtain the latest relevant information on ST products before placing orders. ST products are sold pursuant to ST’s terms and conditions of sale in place at the time of order acknowledgment. Purchasers are solely responsible for the choice, selection, and use of ST products and ST assumes no liability for application assistance or the design of purchasers’ products. No license, express or implied, to any intellectual property right is granted by ST herein. Resale of ST products with provisions different from the information set forth herein shall void any warranty granted by ST for such product. ST and the ST logo are trademarks of ST. For additional information about ST trademarks, refer to www.st.com/trademarks. All other product or service names are the property of their respective owners. Information in this document supersedes and replaces information previously supplied in any prior versions of this document. © 2025 STMicroelectronics – All rights reserved
