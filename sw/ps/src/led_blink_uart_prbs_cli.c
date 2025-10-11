// led_blink_uart_prbs_cli.c — ZynqMP A53, Vitis standalone
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"
#include <string.h>
#include <stdlib.h>
#include "xuartps_hw.h"   // for nonblocking UART RX

// -------- LED (AXI GPIO) --------
#define GPIO_DATA_OFFSET  0x0
#define GPIO_TRI_OFFSET   0x4
#define LED_BASE          XPAR_PL_LED_BASEADDR
//#define LED_ACTIVE_LOW
#ifndef LED_ACTIVE_LOW
  #define LED_ON  1u
  #define LED_OFF 0u
#else
  #define LED_ON  0u
  #define LED_OFF 1u
#endif

// -------- PRBS (AXI-Lite) --------
#if defined(XPAR_PRBS_AXI_STREAM_0_S_AXI_BASEADDR)
  #define PRBS_BASE XPAR_PRBS_AXI_STREAM_0_S_AXI_BASEADDR
#elif defined(XPAR_PRBS_AXI_STREAM_0_BASEADDR)
  #define PRBS_BASE XPAR_PRBS_AXI_STREAM_0_BASEADDR
#else
  #define PRBS_BASE 0xA0000000u
#endif

#define REG_CTRL       0x00
#define REG_STATUS     0x04
#define REG_SEED       0x08
#define REG_FRMLEN     0x0C
#define REG_BYTECNT    0x18
#define REG_BITCNT     0x1C

// CTRL fields/bits
#define CTRL_ENABLE    (1u<<0)
#define CTRL_SW_RESET  (1u<<2)
#define CTRL_MODE_SH   4
#define CTRL_MODE(m)   ((uint32_t)(m) << CTRL_MODE_SH)  // 0:7,1:15,2:23,3:31
#define CTRL_CLEAR     (1u<<15)
// STATUS (R/W1C)
#define ST_RUNNING     (1u<<0)
#define ST_DONE        (1u<<8)

// ---- UART (nonblocking RX on stdin UART) ----
#ifndef STDIN_BASEADDRESS
  #define UART_BASE XPAR_XUARTPS_0_BASEADDR
#else
  #define UART_BASE STDIN_BASEADDRESS
#endif
static inline int uart_getc_nb(void){
  return XUartPs_IsReceiveData(UART_BASE) ? (int)XUartPs_ReadReg(UART_BASE, XUARTPS_FIFO_OFFSET) : -1;
}

// ---- MMIO helpers ----
static inline void wr(uint32_t off, uint32_t v){ Xil_Out32(PRBS_BASE+off, v); }
static inline uint32_t rd(uint32_t off){ return Xil_In32(PRBS_BASE+off); }

// ---- PRBS control helpers ----
static uint32_t g_mode = 3;     // 0:7,1:15,2:23,3:31
static uint32_t g_enable = 1;

static void write_ctrl(uint32_t en, uint32_t mode, uint32_t swr, uint32_t clr){
  wr(REG_CTRL, (en?CTRL_ENABLE:0) | CTRL_MODE(mode) | (swr?CTRL_SW_RESET:0) | (clr?CTRL_CLEAR:0));
}
static void prbs_enable(uint32_t en){ g_enable = en?1:0; write_ctrl(g_enable, g_mode, 0, 0); }
static void prbs_reset(void){ write_ctrl(g_enable, g_mode, 1, 0); }
static void prbs_clear(void){ write_ctrl(g_enable, g_mode, 0, 1); }
static void prbs_set_mode(uint32_t mode){ g_mode = mode & 3u; write_ctrl(g_enable, g_mode, 1, 0); } // reset on mode change
static void prbs_set_frame(uint16_t fl){ wr(REG_FRMLEN, (uint32_t)fl); }
static void prbs_set_seed(uint32_t s){ wr(REG_SEED, s & 0x7FFFFFFFu); } // HW coerces 0->1

static void print_status(void){
  uint32_t st = rd(REG_STATUS);
  uint32_t bc = rd(REG_BYTECNT);
  uint32_t bt = rd(REG_BITCNT);
  xil_printf("[PRBS] STATUS: RUNNING=%u DONE=%u  MODE=%lu  ENABLE=%lu  FRAME=%lu  BYTECNT=%lu  BITCNT=%lu\r\n",
             !!(st&ST_RUNNING), !!(st&ST_DONE),
             (unsigned long)g_mode, (unsigned long)g_enable,
             (unsigned long)rd(REG_FRMLEN),
             (unsigned long)bc, (unsigned long)bt);
}

// ---- CLI ----
static unsigned parse_mode(const char* s){
  if (!strcmp(s,"7"))  return 0;
  if (!strcmp(s,"15")) return 1;
  if (!strcmp(s,"23")) return 2;
  if (!strcmp(s,"31")) return 3;
  // also accept raw 0..3
  unsigned v = (unsigned)strtoul(s, NULL, 0);
  return (v<=3)? v : 3;
}
static uint32_t parse_u32(const char* s){ return (uint32_t)strtoul(s, NULL, (s[0]=='0' && (s[1]=='x'||s[1]=='X'))?16:10); }

static void print_help(void){
  xil_printf("\r\nCommands:\r\n");
  xil_printf("  help                 - this help\r\n");
  xil_printf("  status               - read STATUS/COUNTERS\r\n");
  xil_printf("  enable 0|1           - stop/start PRBS\r\n");
  xil_printf("  mode 7|15|23|31|0..3 - set PRBS poly (auto reset)\r\n");
  xil_printf("  frame <N>            - set FRAME_LEN_BYTES (0=continuous)\r\n");
  xil_printf("  seed <val>           - set SEED (31-bit; 0 coerced in HW)\r\n");
  xil_printf("  reset                - SW_RESET one-shot\r\n");
  xil_printf("  clear                - CLEAR counters\r\n");
  xil_printf("  doneclr              - W1C clear DONE\r\n\r\n");
}

static void handle_line(char *line){
  // tokenize (in-place)
  char *argv[4] = {0}; int argc = 0;
  for (char *p = strtok(line, " \t\r\n"); p && argc < 4; p = strtok(NULL," \t\r\n")) argv[argc++] = p;
  if (argc == 0) return;

  if (!strcmp(argv[0],"help")) { print_help(); return; }
  if (!strcmp(argv[0],"status")) { print_status(); return; }
  if (!strcmp(argv[0],"enable") && argc>=2) { prbs_enable((unsigned)strtoul(argv[1],NULL,0)); print_status(); return; }
  if (!strcmp(argv[0],"mode") && argc>=2)   { prbs_set_mode(parse_mode(argv[1])); print_status(); return; }
  if (!strcmp(argv[0],"frame") && argc>=2)  { prbs_set_frame((uint16_t)strtoul(argv[1],NULL,0)); print_status(); return; }
  if (!strcmp(argv[0],"seed") && argc>=2)   { prbs_set_seed(parse_u32(argv[1]));  print_status(); return; }
  if (!strcmp(argv[0],"reset"))             { prbs_reset();  xil_printf("[PRBS] SW_RESET\r\n"); return; }
  if (!strcmp(argv[0],"clear"))             { prbs_clear();  xil_printf("[PRBS] CLEAR counters\r\n"); return; }
  if (!strcmp(argv[0],"doneclr"))           { wr(REG_STATUS, ST_DONE); xil_printf("[PRBS] DONE cleared\r\n"); return; }

  xil_printf("Unknown/usage error. Type 'help'.\n");
}

int main(void)
{
    xil_printf("\r\nTest Program Started!!!\r\n> ");
    xil_printf("\r\n[Bring-up] LED + UART + PRBS (CLI)\r\n");
    xil_printf(" LED_BASE=0x%08lx  PRBS_BASE=0x%08lx  UART=0x%08lx\r\n",
               (unsigned long)LED_BASE, (unsigned long)PRBS_BASE, (unsigned long)UART_BASE);

    // LED GPIO outputs
    Xil_Out32(LED_BASE + GPIO_TRI_OFFSET, 0x00000000);

    // Start PRBS (defaults)
    g_mode = 3; g_enable = 1;
    prbs_set_seed(1);
    prbs_set_frame(256);
    write_ctrl(g_enable, g_mode, 1, 1); // enable + reset + clear

    // CLI state
    char buf[96]; unsigned idx = 0;
    unsigned led = LED_OFF;
    unsigned printed_running = 0;


    print_help();
    xil_printf("> ");

    while (1) {
        // LED heartbeat (quarter second)
        usleep(250000);
        led = (led==LED_OFF)?LED_ON:LED_OFF;
        Xil_Out32(LED_BASE + GPIO_DATA_OFFSET, led);

        // Nonblocking UART line read
        for (;;) {
            int c = uart_getc_nb();
            if (c < 0) break;
            if (c == '\r' || c == '\n') {
                buf[idx] = 0;
                xil_printf("\r\n");         // echo newline
                handle_line(buf);
                idx = 0;
                xil_printf("> ");
            } else if (c == 0x7F || c == 0x08) { // backspace
                if (idx) { idx--; xil_printf("\b \b"); }
            } else if (idx < sizeof(buf)-1) {
                buf[idx++] = (char)c;
                xil_printf("%c", c);        // echo
            }
        }

        // Optional: print RUNNING once
        uint32_t st = rd(REG_STATUS);
        if ((st & ST_RUNNING) && !printed_running) {
            xil_printf("\r\n[PRBS] Running (first handshake observed)\r\n> ");
            printed_running = 1;
        }
        // Print a frame-notify (optional)
        if (st & ST_DONE) {
            uint32_t bc = rd(REG_BYTECNT);
            wr(REG_STATUS, ST_DONE);
            xil_printf("\r\n[PRBS] DONE (frame bytes=%lu)\r\n> ", (unsigned long)bc);
        }
    }
}
