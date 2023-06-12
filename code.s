/*********************************************************************************
 * Initialize the exception vector table
 ********************************************************************************/
.section    .vectors, "ax"              

        B       _start                      // reset vector
        B       SERVICE_UND                 // undefined instruction vector
        B       SERVICE_SVC                 // software interrrupt vector
        B       SERVICE_ABT_INST            // aborted prefetch vector
        B       SERVICE_ABT_DATA            // aborted data vector
.word       0                               // unused vector
        B       SERVICE_IRQ                 // IRQ interrupt vector
        B       SERVICE_FIQ                 // FIQ interrupt vector


.equ LED_BASE, 0xFF200000 
.equ LED_POINTER_ADDRESS, 0xFFFFea00
.equ ANSWER_POINTER_ADDRESS, 0xFFFFea04 
.equ LED_SAVE_BASE_ADDRESS, 0xFFFFea10 
.equ LED_MAX_SAVE_BASE_ADDRESS, 0xFFFFea60 
.equ RESET_ADDRESS, 0xaaaaaaaa
.equ SW_BASE, 0xFF200040
.equ LED_MASK, 0x3FF
.org    0x1000    // Start at memory location 1000

.equ BIT_SELECT_MASK, 0xE00
.equ TIMER_ADDRESS, 0xff202000
.equ CHAR_MASK, 0b1001111

.text  

Seven_Segment_Base_Addres: .word 0xFF200020
.global     _start                      
_start:                                     
/* Set up stack pointers for IRQ and SVC processor modes */
        MOV     R1, #0b11010010  //| IRQ_MODE 
        MSR     CPSR_c, R1                  // change to IRQ mode
        LDR     SP, =0xFFFFFFFF - 3      // set IRQ stack to top of A9 onchip
        MOV R12,#4 // LED LIGHT COUNTER
		MOV R6,#0
		LDR R0,=LED_POINTER_ADDRESS
		LDR R2,=LED_SAVE_BASE_ADDRESS
		STR R2,[R0]
		BL ResetSavedLedsSTART
		
		

			//BL InitTimer


/* Change to SVC (supervisor) mode with interrupts disabled */
        MOV     R1, #0b11010011  //| SVC_MODE 
        MSR     CPSR_c, R1                  // change to supervisor mode
        LDR     SP, =0x3FFFFFFF - 3            // set SVC stack to top of DDR3 memory

        BL      CONFIG_GIC                  // configure the ARM generic interrupt
                                            // controller
        BL      CONFIG_INTERVAL_TIMER       // configure the Altera interval timer
        BL      CONFIG_KEYS                 // configure the pushbutton KEYs

/* enable IRQ interrupts in the processor */
        MOV     R1, #0b01010011   //| SVC_MODE  // IRQ unmasked, MODE = SVC
        MSR     CPSR_c, R1                  
    	
LOOP:   
		CMP R12,#0
		SUBPLS R12,R12,#1
		BLPL KEY_ISR
		//BPL InitTimer
		BLPL InitTimer
		BL TurnOffLastLed
		//BLLT TurnOffLastLed
		BLPL InitTimer
		BLLT CheckUserSwitchButtonAction
		CMP R6,#4
		BEQ ResetGame
        B LOOP                        
                      
/* Configure the Altera interval timer to create interrupts at 50-msec intervals */
CONFIG_INTERVAL_TIMER:   
        LDR     R0, =0xFF202000             
/* set the interval timer period for scrolling the LED displays */
        LDR     R1, =0b10011000100101101000000  // 1/(100 MHz) x 5x10^6 = 50 msec
        STR     R1, [R0,#8]                  // store the low half word of counter
                                            // start value
        LSR     R1, R1, #16                 
        STR     R1, [R0,#12]                  // high half word of counter start value

                                            // start the interval timer, enable its interrupts
        MOV     R1, #0b111                  // START = 1, CONT = 1, ITO = 1
        STR     R1, [R0,#4]                  
        BX      LR                          

/* Configure the pushbutton KEYS to generate interrupts */
CONFIG_KEYS:                                
                                            // write to the pushbutton port interrupt mask register
        LDR     R0, =0xff200050             // pushbutton key base address
        MOV     R1, #0xF                    // set interrupt mask bits
        STR     R1, [R0, #0x8]              // interrupt mask register is (base + 8)
        BX      LR                          
		
/* This file:
 * 1. defines exception vectors for the A9 processor
 * 2. provides code that initializes the generic interrupt controller
 */

/*--- IRQ ---------------------------------------------------------------------*/
           
SERVICE_IRQ:                            
        PUSH    {R0-R7, LR}             

/* Read the ICCIAR from the CPU interface */
        LDR     R4, =0xFFFEC100   
        LDR     R5, [R4, #0x0C]       // read the interrupt ID

INTERVAL_TIMER_CHECK:                   
        CMP     R5, #72 // check for FPGA timer interrupt
        BNE     KEYS_CHECK              

        BL      TIMER_ISR               
        B       EXIT_IRQ                

KEYS_CHECK:                             
        CMP     R5, #73           
UNEXPECTED:                             
        BNE     UNEXPECTED              // if not recognized, stop here

        BL      KEY_ISR                 
EXIT_IRQ:                               
/* Write to the End of Interrupt Register (ICCEOIR) */
        STR     R5, [R4, #0x10]      

        POP     {R0-R7, LR}             
        SUBS    PC, LR, #4              


/*--- Undefined instructions --------------------------------------------------*/
.global     SERVICE_UND             
SERVICE_UND:                            
        B       SERVICE_UND             

/*--- Software interrupts -----------------------------------------------------*/
.global     SERVICE_SVC             
SERVICE_SVC:                            
        B       SERVICE_SVC             

/*--- Aborted data reads ------------------------------------------------------*/
.global     SERVICE_ABT_DATA        
SERVICE_ABT_DATA:                       
        B       SERVICE_ABT_DATA        

/*--- Aborted instruction fetch -----------------------------------------------*/
.global     SERVICE_ABT_INST        
SERVICE_ABT_INST:                       
        B       SERVICE_ABT_INST        

/*--- FIQ ---------------------------------------------------------------------*/
.global     SERVICE_FIQ             
SERVICE_FIQ:                            
        B       SERVICE_FIQ             

/*
 * Configure the Generic Interrupt Controller (GIC)
 */
.global     CONFIG_GIC              
CONFIG_GIC:                             
           
/* configure the FPGA IRQ0 (interval timer) and IRQ1 (KEYs) interrupts */
        LDR     R0, =0xFFFED848         // ICDIPTRn: processor targets register
        LDR     R1, =0x00000101         // set targets to cpu0
        STR     R1, [R0]                

        LDR     R0, =0xFFFED108         // ICDISERn: set enable register
        LDR     R1, =0x00000300         // set interrupt enable
        STR     R1, [R0]                

/* configure the GIC CPU interface */
        LDR     R0, =0xFFFEC100   // base address of CPU interface
/* Set Interrupt Priority Mask Register (ICCPMR) */
        LDR     R1, =0xFFFF             // 0xFFFF enables interrupts of all
                                        // priorities levels
        STR     R1, [R0, #0x04]       
/* Set the enable bit in the CPU Interface Control Register (ICCICR). This bit
 * allows interrupts to be forwarded to the CPU(s) */
        MOV     R1, #0x1             
        STR     R1, [R0, #0x00]       

/* Set the enable bit in the Distributor Control Register (ICDDCR). This bit
 * allows the distributor to forward interrupts to the CPU interface(s) */
        LDR     R0, =0xFFFED000    
        STR     R1, [R0, #0x00]       
        BX      LR                                             

KEY_ISR:
        LDR     R0, =0xff200050   // base address of pushbutton KEY parallel port
        LDR     R1, [R0, #0xC]  // read edge capture register
        STR     R1, [R0, #0xC]  // clear the interrupt
		MOV R1,#1
		LDR R2,=TIMER_ADDRESS
		STR R1,[R2,#16]
		LDR R2 ,[R2,#16]
		LDR R3,=BIT_SELECT_MASK
		//AND R2,R2,R3
		AND R2,R2,R3
		LSR R2,R2,#9
		//LSR R2,R2,#10

		MOV R10,R2
		MOV R9,#1
		B CalculateLedPlace
		//B InitTimer
		//B END_KEY_ISR

CalculateLedPlace:
	CMP R10,#0
	BEQ InitTimer
	SUB R10,R10,#1
	LSL R9,R9,#1
	B CalculateLedPlace


TIMER_ISR:                      
        PUSH    {R0-R11}         
        LDR     R1, =0xFF202000 // interval timer base address
        MOVS    R0, #0          
        STR     R0, [R1]        // clear the interrupt

        LDR R0,=LED_BASE   // LED base address
		LDR R1,=SW_BASE
		LDR R2,=LED_MASK
		LDR R11, [R1]

END_TIMER_ISR:                  
        POP     {R0-R11}         
        BX      LR

	
	
	
	
	
InitTimer:
	//Init Timer
	LDR R7, =0xFFFEC600 // PRIVATE TIMER
	LDR R8,=240000000
	STR R8,[R7]
	MOV R8, #0b011 
	STR R8, [R7, #0x8] 	
	B WAIT
WAIT: 
	LDR R8, [R7, #0xC] // read timer status
	CMP R8, #0
	BEQ WAIT
	STR R8, [R7, #0xC]
	
	LDR R0,=LED_SAVE_BASE_ADDRESS
	LDR R1,=LED_POINTER_ADDRESS
	LDR R1,[R1]
	B SaveLeds
SaveLeds:
	LDR R2,[R1]
	//LDR R2,[R2]
	CMP R2,#0
	BEQ END_KEY_ISR
	LDR R3,=RESET_ADDRESS
	CMP R2,R3
	BEQ END_KEY_ISR
	ADD R1,R1,#4
	B SaveLeds
TurnOffLastLed:
	LDR R1, =LED_BASE
	MOV R9,#0
	STR R9,[R1]
	//MOV R12,#0
  	BX  LR 
	
	
ResetSavedLedsSTART:
	LDR R0,=LED_SAVE_BASE_ADDRESS
	//MOV R12,#0
	B ResetSavedLedsLOOP
ResetSavedLedsLOOP:
	LDR R3,=RESET_ADDRESS
	LDR R2,[R0]
	LDR R4,=RESET_ADDRESS
	CMP R2,R4
	BEQ ResetSavedLedsFINISH
	STR R3,[R0]
	ADD R0,R0,#4
	B ResetSavedLedsLOOP
ResetSavedLedsFINISH:
	LDR R0,=LED_SAVE_BASE_ADDRESS
	LDR R1,=LED_POINTER_ADDRESS
	LDR R0,[R1]
	BX LR

CheckUserSwitchButtonAction:
	LDR R0,=SW_BASE
	LDR R0,[R0]
	CMP R0,#0
	BXEQ LR
	LDR R0,=LED_SAVE_BASE_ADDRESS
	MOV R3,#0
	B GetCurrentLedAddress
GetCurrentLedAddress:
	CMP R6,R3
	BEQ CheckIFSwitchAnswerCorrect
	ADD R3,R3,#1
	ADD R0,R0,#4
	B GetCurrentLedAddress
	//BEQ CheckIFSwitchAnswerCorrect
CheckIFSwitchAnswerCorrect:
	ADD R6,R6,#1
	LDR R0,[R0]
	LDR R1,=SW_BASE
	LDR R1,[R1]
	CMP R0,R1
	BEQ CorrectContinueGame
	B END
	
CorrectContinueGame:
	LDR R0,=SW_BASE
	LDR R0,[R0]
	CMP R0,#0
	BXEQ LR
	B CorrectContinueGame

ResetGame:
	MOV R6,#0
	MOV R12,#4
	BX LR
	
END_KEY_ISR:
		STR R9,[R1]//PUT LED ADDRESES
		LDR R2,=LED_POINTER_ADDRESS
		STR R1,[R2]
		LDR R1, =LED_BASE
		STR R9,[R1]
        BX  LR  

END:
	B END

.global     PATTERN                     
PATTERN:                                    
.word       0x0F0F0F0F                  // pattern to show on the LED lights
.global     KEY_DIR                   
KEY_DIR:                                  
.word       0  
.end
ee306_timerInt_cpulator.txt
Displaying ee306_timerInt_cpulator.txt.
