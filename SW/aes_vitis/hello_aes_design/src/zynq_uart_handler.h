#ifndef ZYNQ_UART_HANDLER_H
#define ZYNQ_UART_HANDLER_H

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xil_io.h"

#include "xuartps.h"
// #include "defines.h"
// #include "global.h"

extern XUartPs Uart_Ps;

//fuction decleration
u32* listen_to_com();
void initilize_uart();





#endif