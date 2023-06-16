
.section    .vectors, "ax"              

        B       _start                      // reset vector
        B       SERVICE_UND                 // undefined instruction vector
        B       SERVICE_SVC                 // software interrrupt vector
        B       SERVICE_ABT_INST            // aborted prefetch vector
        B       SERVICE_ABT_DATA            // aborted data vector
.word       0                               // unused vector
        B       SERVICE_IRQ                 // IRQ interrupt vector
        B       SERVICE_FIQ                 // FIQ interrupt vector


// After every lamp is glow it is stored in the memory addresses according to the
// current value in the LED_POINTER_ADDRESS, it starts to store glowed 
// from LED_SAVE_BASE_ADDRESS  until LED_MAX_SAVE_BASE_ADDRESS
.equ UART_BASE, 0xFF201000
.equ LED_BASE, 0xFF200000 
.equ LED_POINTER_ADDRESS, 0xFFFFea00 // Points the current read address of the LED save address
.equ LED_SAVE_BASE_ADDRESS, 0xFFFFea10 // Address that LEDs started to be saved
.equ LED_MAX_SAVE_BASE_ADDRESS, 0xFFFFea60 // Max possible LED save address
.equ TOTAL_SCORE_SAVE_ADDRESS, 0xFFFFea04 // Holds the total score value in that address
.equ LED_COUNT_ADDRESS, 0xFFFFea08 // Holds the LED count that will be grown in every new iteration of the game
.equ WIN_COUNT_ADDRESS, 0xFFFFea0c // Holds the total win value in that address
.equ RESET_ADDRESS, 0xaaaaaaaa // Allows the resetting of pre-stored values in the memory by writing them to the relevant addresses.
.equ SW_BASE, 0xFF200040 // Base addresses of the switches
.org    0x1000    // Start at memory location 1000

.equ BIT_SELECT_MASK, 0xE00 // Allows masking the random time interval value by taking its last three bits
.equ TIMER_ADDRESS, 0xff202000

.text  
HEXTABLE: .word 0b00111111,0b00000110,0b01011011,0b01001111,0b01100110,0b01101101,0b01111101,0b00000111,0b01111111,0b01101111
Seven_Segment_Base_Addres: .word 0xFF200020
.global     _start                      
_start:                                     
/* Set up stack pointers for IRQ and SVC processor modes */
        MOV     R1, #0b11010010  //| IRQ_MODE 
        MSR     CPSR_c, R1                  // change to IRQ mode
        LDR     SP, =0xFFFFFFFF - 3      // set IRQ stack to top of A9 onchip
		

        MOV R12,#3 // glow LED count at start it decreases after every sucessfull attemp to 
		// Loads glow LED count to relevant address
		LDR R6,=LED_COUNT_ADDRESS
		STR R12,[R6]
		
		// Holds the current correctly matched LED switch pair count; 
		// It is used in order to check if the user matched all LEDs in a game iteration. 
		// It resets after every iteration.
		MOV R6,#0
		
		// Sets win count value to the zero
		LDR R11,=WIN_COUNT_ADDRESS
		STR R6,[R11]

		BL Reset_Seven_Segment_Display // Resets the values in the display
		
		// Closes all of the LEDs
		LDR R0,=LED_BASE
		STR R6,[R0]
		
		// Initializes the LED pointer address value to the base address 
		// value to start pointing and putting values from the base address.
		LDR R0,=LED_POINTER_ADDRESS
		LDR R2,=LED_SAVE_BASE_ADDRESS
		STR R2,[R0]
		LDR R0,=TOTAL_SCORE_SAVE_ADDRESS
		STR R6,[R0]
		
		
		
		PUSH {R0-R10}
		LDR  R6, =WELCOME_STRING
		BL LoadText
		POP {R0-R10}
		
		BL ResetSavedLedsSTART // Resets pre-stored LED values in the addresses
		BLPL InitTimer // Delay for 2.4 seconds



/* Change to SVC (supervisor) mode with interrupts disabled */
        MOV     R1, #0b11010011  //| SVC_MODE 
        MSR     CPSR_c, R1                  // change to supervisor mode
        LDR     SP, =0x3FFFFFFF - 3            // set SVC stack to top of DDR3 memory

        BL      CONFIG_GIC                  // configure the ARM generic interrupt
                                            // controller
        BL      CONFIG_INTERVAL_TIMER       // configure the Altera interval timer
        BL      CONFIG_KEYS                 // configure the pushbutton KEYs

		LDR R0, =UART_BASE // UART base address
		MOV R1, #0xF // set interrupt mask bits
		STR R1, [R0, #0x4] // interrupt mask register (base + 8)
	
/* enable IRQ interrupts in the processor */
        MOV     R1, #0b01010011   //| SVC_MODE  // IRQ unmasked, MODE = SVC
        MSR     CPSR_c, R1  
		

// Main loop of the game, which controls the overall life cycle of the system.		   	
LOOP:   // If R12 is positive, the system checks if, 
		// in the current game iteration, 
		// more leads need to be glowed before allowing the user to push switches.
		CMP R12,#0
		SUBPLS R12,R12,#1
		BLPL GlowLed
		BlPl SaveLeds
		BLPL InitTimer
		
		//Extinguishes the last glowed LED, and 
		// before glowing another waits for 2.4 seconds.
		BL TurnOffLastLed
		BLPL InitTimer
		
		// Checks user's interactions with the switch buttons
		BLLT CheckUserSwitchButtonAction
		
		// Checks if the user found all the LED-switch pairs correctly in a game iteration; 
		// if so, start a new game iteration.
		LDR R0,=LED_COUNT_ADDRESS
		LDR R0,[R0]
		CMP R6,R0
		BLEQ ResetGame
		
		
        B LOOP  // Return the loop                      
                      
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

//UAT_CHECK:
//	CMP R5, #80
//	BEQ UAT_INTERRUPT
	
	
KEYS_CHECK:                             
        CMP     R5, #73           
UNEXPECTED:                             
        BNE     UNEXPECTED              // if not recognized, stop here

        BL      GlowLed                 
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
		BX LR


// It glows a random LED when the function is triggered; 
// the randomness depends on the current value of the interval timer. 
// It takes the last three bits of the interval timer's value by using the timer mask and, 
// according to these three bits, calculates which LED it will glow.
GlowLed:
		// Chooses a random value from 0 to 8
		MOV R1,#1
		LDR R2,=TIMER_ADDRESS
		STR R1,[R2,#16]
		LDR R2 ,[R2,#16]
		LDR R3,=BIT_SELECT_MASK
		AND R2,R2,R3
		LSR R2,R2,#9

		// Put a random value in R10 and initialize R9 with 1 
		//to prepare to find a binary value that will glow a LED in the system.
		MOV R10,R2
		MOV R9,#1
		B CalculateLedPlace

		
// According to the random value that is put in R10, 
// it starts to iterate, and each iteration decreases this value by one 
// and shifts R9 to the left in order to obtain 
// the relevant value that can glow a random LED. 
// When R10 is zero, it finds the LED that needs to glow.
CalculateLedPlace:
	CMP R10,#0
	BEQ InitTimer
	SUB R10,R10,#1
	LSL R9,R9,#1
	B CalculateLedPlace

// Reset Interval Timer
TIMER_ISR:                      
        PUSH    {R0-R11}         
        LDR     R1, =0xFF202000 // interval timer base address
        MOVS    R0, #0          
        STR     R0, [R1]        // clear the interrupt

END_TIMER_ISR:                  
        POP     {R0-R11}         
        BX      LR

	
	
	
	
// This timer provides 2.4 seconds delay when it is called.	
InitTimer:
	// Initializes the Timer with 2.4 seconds
	LDR R7, =0xFFFEC600 // PRIVATE TIMER
	LDR R8,=240000000 // 240000000 / 100 MHz = 2.4 sec
	STR R8,[R7]
	MOV R8, #0b011 
	STR R8, [R7, #0x8] 	
	B WAIT
	
// Loops in the WAIT function until the private timer finishes 2.4 seconds
WAIT: 
	LDR R8, [R7, #0xC] // read timer status
	CMP R8, #0
	BEQ WAIT // Continue if it is not finished
	STR R8, [R7, #0xC]
	
	LDR R0,=LED_SAVE_BASE_ADDRESS
	LDR R1,=LED_POINTER_ADDRESS
	LDR R1,[R1]
	B END_KEY_ISR
	

// Saves the LED's value to the relevant addresses, 
// which are pointed to by the LED pointer address value.	
SaveLeds:
	LDR R2,[R1]
	CMP R2,#0
	BEQ END_SAVE
	LDR R3,=RESET_ADDRESS
	CMP R2,R3
	BEQ END_SAVE
	ADD R1,R1,#4
	B SaveLeds
// Sets off to the last glowed LED.
TurnOffLastLed:
	LDR R1, =LED_BASE
	MOV R9,#0
	STR R9,[R1]
  	BX  LR 
	
// Start function for resetting the pre-stored LED values in the addresses.	
ResetSavedLedsSTART:
	LDR R0,=LED_SAVE_BASE_ADDRESS
	B ResetSavedLedsLOOP
	
// Iterates over all the saved LED data and resets them by overwriting 
// them by using the value in the reset address which is "0xaaaaaaaa"
ResetSavedLedsLOOP:
	LDR R3,=RESET_ADDRESS
	LDR R2,[R0]
	LDR R4,=RESET_ADDRESS
	CMP R2,R4
	BEQ ResetSavedLedsFINISH
	STR R3,[R0]
	ADD R0,R0,#4
	B ResetSavedLedsLOOP
	
// Finishes the operation and also resets LED pointer to the base address.
ResetSavedLedsFINISH:
	LDR R0,=LED_SAVE_BASE_ADDRESS
	LDR R1,=LED_POINTER_ADDRESS
	STR R0,[R1]
	BX LR
// Checks if the user pushed a switch button or not; 
// if so, check if he pushed the switch 
// buttons in an order that matches the order of the LEDs' glow.
CheckUserSwitchButtonAction:
	LDR R0,=SW_BASE
	LDR R0,[R0]
	CMP R0,#0
	BXEQ LR
	LDR R0,=LED_SAVE_BASE_ADDRESS
	MOV R3,#0
	B GetCurrentLedAddress

// Finds the address of the currently LED 
// redirects to CheckIFSwitchAnswerCorrect method 
// to check if clicked switch matches with the current LED.
GetCurrentLedAddress:
	CMP R6,R3
	BEQ CheckIFSwitchAnswerCorrect
	ADD R3,R3,#1
	ADD R0,R0,#4
	B GetCurrentLedAddress

// Checks if the switch and LED are matching 
// by comparing their values because, for both of the devices, 
// the working principle of the values is the same. For instance, 
// when you press the first button on the switch, 
// the binary value is 1. Similarly, if you want the first LED to glow, 
// you must have written the binary value 1. So they can be compared easily.
CheckIFSwitchAnswerCorrect:
	ADD R6,R6,#1
	LDR R0,[R0]
	LDR R1,=SW_BASE
	LDR R1,[R1]
	CMP R0,R1
	BEQ CorrectContinueGame
	B LOSE

// Triggers when switch and key is matching, 
// waits until user resets the relevant switch button, 
// after that runs UpdateScoreAndReturn 
CorrectContinueGame:
	LDR R0,=SW_BASE
	LDR R0,[R0]
	CMP R0,#0
	BEQ UpdateScoreAndReturn
	B CorrectContinueGame

// Increases the current score, displays it on the seven segment display 
// and return to the loop
UpdateScoreAndReturn:
	LDR R1,=TOTAL_SCORE_SAVE_ADDRESS
	LDR R0,[R1]
	ADD R0,R0,#10
	STR R0,[R1]
	
	
	PUSH {R0-R10,LR}
	MOV R9,R0
	B DisplayScore


// Resets the current iteration of the game, it triggers 
// when you found sequence of LEDS correctly, 
// it prepares for a new game iteration.
ResetGame:
	PUSH {LR}
	BLPL InitTimer
	LDR R6,=WIN_COUNT_ADDRESS
	LDR R11,[R6]
	ADD R11,R11,#1
	STR R11,[R6]
	
	LSL R11,R11,#31
	CMP R11,#0
	
	LDR R0,=LED_COUNT_ADDRESS
	
	BLEQ IncreaseLedCount
	POP {LR}
	MOV R6,#0

	LDR R0,[R0]
	MOV R12,R0
	B ResetSavedLedsSTART


// Every time you win two game iterations, 
// the game increases the difficulty by adding 1 more LED to the sequence.
IncreaseLedCount:
	LDR R11,[R0]
	ADD R11,R11,#1
	STR R11,[R0]
	BX LR

// Ends the saving process by updating the LED pointer address to the next address
END_SAVE:
	STR R9,[R1]//PUT LED ADDRESES
	LDR R2,=LED_POINTER_ADDRESS
	STR R1,[R2]
	LDR R1, =LED_BASE
	STR R9,[R1]
	B END_KEY_ISR

// End method that redirects to main LOOP
END_KEY_ISR:
        BX  LR  

// Triggers when you lose the game, Opens all of the LEDS
LOSE:
	LDR R0,=LED_BASE
	LDR R1,=0b1111111111
	STR R1,[R0]
	B END
// ENDING FUNCTION
END:
	B END


// Loads the text and by using 
// it's helper functions prints the relevant text to the JTAG UART.
LoadText:
	//Init Timer
	LDR R11, =0xFFFEC600 // PRIVATE TIMER
	LDR R10,=12000000
	STR R10,[R11]
	MOV R10, #0b011 
	STR R10, [R11, #0x8] 

	LDR  r1, =UART_BASE
	MOV R8,R7
	MOV R7,R6
	B WriteText
// Writes the text inside the address in the R6 register
// until reading the memory address which is empty.
WriteText:
	LDRB r0, [R7]    // load a single byte from the string
	CMP  r0, #0
	BEQ  END_Write_Text  // stop when the null character is found
	CMP  r0, #0xaa
	BEQ  END_Write_Text
	B WAITUAT
	
Write_Text_Helper:
	STR  r0, [r1]    // copy the character to the UART DATA field
	ADD  R7, R7, #1  // move to next character in memory
	B WriteText
	
// Ends write text 
END_Write_Text:
	MOV R7,R8
	MOV R8,#0
	MOV R10, #0b000
	STR R10, [R11, #0x8] 
	BX LR
	
// Waits for a while after every character is written
WAITUAT: 
	LDR R10, [R11, #0xC] // read timer status
	CMP R10, #0
	BEQ WAITUAT
	STR R10, [R11, #0xC] 
	B Write_Text_Helper	
	
DisplayScore:
	MOV R0, R9
	LDR R2, Seven_Segment_Base_Addres
	MOV R3, #0 // COUNTER_THOUSAND (Holds 1000's digit)
	MOV R4, #0 // COUNTER_HUNDRED (Holds 100's digit)
	MOV R5, #0 // COUNTER_TEN (Holds 10's digit)
	MOV R6, #0 // COUNTER_ONE (Holds 1's digit)
	MOV R7, #0 // 
	MOV R8, #0 // 
	MOV R9, #0 // 
	B IS_THERE_THOUSAND

Get_Zero_Hexa:
	LDR R8, [R7]
	BX LR
// Finds Hexa number for relevant value
FIND_HEXA_NUMBER:
	CMP R9,#0
	BEQ Get_Zero_Hexa
	
	LDR R8, [R7] , #4
	SUB R9,R9,#1
	CMP R9,#0
	BNE FIND_HEXA_NUMBER
	LDR R8, [R7]
	BX LR

// Checks if the current number has 1000's digit
IS_THERE_THOUSAND:
	CMP R0,#1000
	BGE LOOP_THOUSAND
	LDR R3 ,HEXTABLE
	B IS_THERE_HUNDRED
// Checks if the current number has 100's digit
IS_THERE_HUNDRED:
	CMP R0,#100
	BGE LOOP_HUNDRED
	LDR R4 ,HEXTABLE
	B IS_THERE_TEN
// Checks if the current number has 10's digit
IS_THERE_TEN:
	CMP R0,#10
	BGE LOOP_TEN
	LDR R5 ,HEXTABLE
	B LOOP_ONE
// Loops in 1000's until find the value of 1000's digit
LOOP_THOUSAND://R3
	SUB R0,R0,#1000
	CMP R0,#1000
	ADD R3,R3,#1
	BGE LOOP_THOUSAND
	
	LDR R7,=HEXTABLE
	MOV R9,R3
	BL FIND_HEXA_NUMBER
	MOV R3,R8
	MOV R8,#0
	B IS_THERE_HUNDRED
// Loops in 100's until find the value of 100's digit
LOOP_HUNDRED://R4
	SUB R0,R0,#100
	CMP R0,#100
	ADD R4,R4,#1
	BGE LOOP_HUNDRED
	
	LDR R7,=HEXTABLE	
	MOV R9,R4
	BL FIND_HEXA_NUMBER
	MOV R4,R8
	MOV R8,#0
	
	B IS_THERE_TEN
// Loops in 10's until find the value of 10's digit
LOOP_TEN://R5
	SUB R0,R0,#10
	CMP R0,#10
	ADD R5,R5,#1
	BGE LOOP_TEN
	
	LDR R7,=HEXTABLE	
	MOV R9,R5
	BL FIND_HEXA_NUMBER
	MOV R5,R8
	MOV R8,#0
	
	B LOOP_ONE
// Not run looping in the 1's, directly gets the remainder value
LOOP_ONE://R6
	MOV R6,R0
	LDR R7,=HEXTABLE	
	MOV R9,R6
	BL FIND_HEXA_NUMBER
	MOV R6,R8
	MOV R8,#0
	B Write_All_Digits
// Writes all found digits to the seven-segment display
Write_All_Digits:
	MOV R0,#0
	ADD R0,R0,R6
	LSL R5, #8
	ADD R0,R0,R5
	LSL R4, #16
	ADD R0,R0,R4
	LSL R3, #24
	ADD R0,R0,R3
	STR R0,[R2]
	CMP R10,#1
	POP {R0-R10,LR}
	BX LR
	
// Resets the value sto the 0 in the display
Reset_Seven_Segment_Display:
	LDR R2, Seven_Segment_Base_Addres
	MOV R1,#0b00111111
	MOV R0,#0b00111111
	LSL R1, #8
	ADD R0,R0,R1
	STR R0,[R2]

	BX LR

.global     PATTERN                     
PATTERN:                                    
.word       0x0F0F0F0F                  // pattern to show on the LED lights
.global     KEY_DIR                   
KEY_DIR:                                  
.word       0 

.data  // Data Section
WELCOME_STRING: 
.asciz    "\n Hello, Welcome to the Arda Says Game ! "

.end


