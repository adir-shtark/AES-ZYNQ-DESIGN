#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "sleep.h"
#include "xparameters.h"
#include "zynq_uart_handler.h"

// Helper function to check if the DMA channel is halted
u32 checkHalted(u32 baseAddress, u32 offset);

// Lookup the XAxiDma_Config struct using the base address
XAxiDma_Config *XAxiDma_LookupConfigBaseAddr(UINTPTR BaseAddress);

// Implementation of lookup function
XAxiDma_Config *XAxiDma_LookupConfigBaseAddr(UINTPTR BaseAddress) {
    extern XAxiDma_Config XAxiDma_ConfigTable[];
    int i;

    // Iterate through the configuration table to find the matching base address
    for (i = 0; i < XPAR_XAXIDMA_NUM_INSTANCES; i++) {
        if (XAxiDma_ConfigTable[i].BaseAddr == BaseAddress) {
            return &XAxiDma_ConfigTable[i];
        }
    }

    return NULL; // If not found
}



int main() {
    init_platform();
    initilize_uart(); // fixed typo

    u32 c[8] = {0};
    u32 status;

    XAxiDma_Config *myDmaConfig;
    XAxiDma myDma;

    myDmaConfig = XAxiDma_LookupConfigBaseAddr(XPAR_AXI_DMA_0_BASEADDR);
    status = XAxiDma_CfgInitialize(&myDma, myDmaConfig);
    if (status != XST_SUCCESS) {
        print("DMA initialization failed\n\r");
        return -1;
    }
    print("DMA initialization success..\n\r");


    xil_printf("listen to com---------\n\r");
    u32* message = listen_to_com(); // Make sure to implement properly
    u32 message_len = 32; // Replace with actual length from your message

    Xil_DCacheFlushRange((UINTPTR)message, message_len);
    Xil_DCacheFlushRange((UINTPTR)c, sizeof(c));

    XAxiDma_SimpleTransfer(&myDma, (UINTPTR)message, message_len, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_SimpleTransfer(&myDma, (UINTPTR)c, sizeof(c), XAXIDMA_DEVICE_TO_DMA);

    while (XAxiDma_Busy(&myDma, XAXIDMA_DMA_TO_DEVICE));
    while (XAxiDma_Busy(&myDma, XAXIDMA_DEVICE_TO_DMA));
    Xil_DCacheInvalidateRange((UINTPTR)c, sizeof(c));

    print("\n\rDMA transfer success..\n\r");

    // Print c as characters
    u8* char_output = (u8*)c;
    int output_len = 12; // Adjust to actual length your IP returns
    xil_printf("Processed Output: ");
    for (int i = 0; i < output_len; i++) {
        xil_printf("%c", char_output[i]);
    }


    xil_printf("\r\nlisten to com---------\n\r");
    u32* message2 = listen_to_com(); // Make sure to implement properly
    u32 message_len2 = 32; // Replace with actual length from your message

    Xil_DCacheFlushRange((UINTPTR)message2, message_len2);
    Xil_DCacheFlushRange((UINTPTR)c, sizeof(c));

    XAxiDma_SimpleTransfer(&myDma, (UINTPTR)message2, message_len2, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_SimpleTransfer(&myDma, (UINTPTR)c, sizeof(c), XAXIDMA_DEVICE_TO_DMA);

    while (XAxiDma_Busy(&myDma, XAXIDMA_DMA_TO_DEVICE));
    while (XAxiDma_Busy(&myDma, XAXIDMA_DEVICE_TO_DMA));
    Xil_DCacheInvalidateRange((UINTPTR)c, sizeof(c));

    print("\n\rDMA transfer success..\n\r");


    // Print c as characters
    u8* char_output2 = (u8*)c;
    int output_len2 = 12; // Adjust to actual length your IP returns
    xil_printf("Processed Output: ");
    for (int i = 0; i < output_len2; i++) {
        xil_printf("%c", char_output2[i]);
    }

    cleanup_platform();
    return 0;
}












// Function to check if a DMA channel (MM2S or S2MM) is halted
// Use offset = 0x4 for MM2S, 0x34 for S2MM
u32 checkHalted(u32 baseAddress, u32 offset) {
    u32 status = (XAxiDma_ReadReg(baseAddress, offset)) & XAXIDMA_HALTED_MASK;
    return status;
}
