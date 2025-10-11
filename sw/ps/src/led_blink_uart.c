// led_blink_uart.c — ZynqMP A53, Vitis standalone (no platform.h)
#include "xparameters.h"   // XPAR_PL_LED_BASEADDR, STDOUT/STDIN mapping
#include "xil_io.h"        // Xil_Out32, Xil_In32
#include "xil_printf.h"    // xil_printf
#include "sleep.h"         // sleep()

// AXI GPIO (single-channel) register offsets
#define GPIO_DATA_OFFSET  0x0
#define GPIO_TRI_OFFSET   0x4

// From your xparameters.h
#define LED_BASE          XPAR_PL_LED_BASEADDR   // 0x80010000

// Uncomment if your LED is active-low
// #define LED_ACTIVE_LOW

#ifndef LED_ACTIVE_LOW
  #define LED_ON   1u
  #define LED_OFF  0u
#else
  #define LED_ON   0u
  #define LED_OFF  1u
#endif

int main(void)
{
    xil_printf("\r\n[LED] Blink + UART test (LED_BASE=0x%08lx)\r\n",
               (unsigned long)LED_BASE);

    // Make channel-1 pins outputs (0 = output)
    Xil_Out32(LED_BASE + GPIO_TRI_OFFSET, 0x00000000);

    unsigned led = LED_OFF;
    while (1) {
        led = (led == LED_OFF) ? LED_ON : LED_OFF;
        Xil_Out32(LED_BASE + GPIO_DATA_OFFSET, led);
        xil_printf("Hello World!\r\n");
        sleep(1);
    }
}
