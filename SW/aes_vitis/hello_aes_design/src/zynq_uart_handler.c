
#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xil_io.h"

#include "zynq_uart_handler.h"
#include "xuartps.h"
// #include "defines.h"
// #include "global.h"

XUartPs Uart_Ps;


//function bodys
void initilize_uart()
{
    
    XUartPs_Config *Config;
    int status;
    // Initialize UART
    Config = XUartPs_LookupConfig(XPAR_UART0_BASEADDR);
    status = XUartPs_CfgInitialize(&Uart_Ps, Config, Config->BaseAddress);
    
}


u32* listen_to_com()
{
    while(1)
    {
   
        //for uart
        u8 RecvChar;
        static u8 Buffer[32];//srting
        static int Index = 0;

        if (XUartPs_IsReceiveData(Uart_Ps.Config.BaseAddress)) {        
            
            //Read one byte from UART
            RecvChar = XUartPs_RecvByte(Uart_Ps.Config.BaseAddress);
            xil_printf("%c", RecvChar);

            //Check for end of line (Enter key) (recive string)
            if (RecvChar == '\r' || RecvChar == '\n')
            {
                // Null-terminate the string
                Buffer[Index] = '\0';
                memset(Buffer + Index + 1, 0, 32 - Index - 1); // optional
                //Reset index for next message
                Index = 0;

                //Print the received string
                //xil_printf("\r\nYou sent: %s\r\n", Buffer);
                return Buffer;
                    
            } 
            else 
            {
                // Store the character in buffer (if room)
                if (Index < 32 - 1)
                {
                    Buffer[Index++] = RecvChar;
                }
                else
                {
                    // Buffer overflow: reset
                    xil_printf("\r\nBuffer overflow. Message too long.\r\n");
                    Index = 0;
                }
            }
        }          
    }
}




