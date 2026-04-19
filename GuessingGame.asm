; GuessingGame.asm
; SW8: P1 Lock
; SW7: P2 Lock
; SW9: Start

ORG 0

; Reset Hex screens and LEDs
Init:
    LOADI 0
    OUT Hex0
    OUT Hex1
    OUT LEDs

; P1 sets P2 target
WaitP1Set:
    IN CH0
    CALL ScaleTo99
    STORE P2Target      
    CALL PackDecimal
    OUT Hex1            
    IN Switches
    AND Mask8           
    JZERO WaitP1Set
WaitP1Release:
    IN Switches
    AND Mask8
    JNZ WaitP1Release
    LOADI 0
    OUT Hex1            

; P2 sets P1 target
WaitP2Set:
    IN CH7
    CALL ScaleTo99
    STORE P1Target      
    CALL PackDecimal
    OUT Hex0            
    IN Switches
    AND Mask7           
    JZERO WaitP2Set
WaitP2Release:
    IN Switches
    AND Mask7
    JNZ WaitP2Release
    LOADI 0
    OUT Hex0            

; Wait until Start switch is up
WaitMasterStart:
    IN Switches
    AND Mask9
    JZERO WaitMasterStart 

; Reset timer
StartTimer:
    LOADI 0
    OUT Timer

; Game loop for P1 and P2 to guess their respective targets
GameLoop:
    IN CH0
    CALL ScaleTo99
    STORE P1Guess
    CALL PackDecimal
    OUT Hex1            

    IN CH7
    CALL ScaleTo99
    STORE P2Guess
    CALL PackDecimal
    OUT Hex0            

    IN Timer
    STORE TimerVal
    SUB Const50
    JPOS RoundOver
    JZERO RoundOver

    ; LED countdown
    LOAD TimerVal
    SUB Const10
    JNEG LED5
    LOAD TimerVal
    SUB Const20
    JNEG LED4
    LOAD TimerVal
    SUB Const30
    JNEG LED3
    LOAD TimerVal
    SUB Const40
    JNEG LED2
    JUMP LED1

; Helper subroutines to set LEDs
LED5: LOADI &B011111
    OUT LEDs
    JUMP GameLoop
LED4: LOADI &B001111
    OUT LEDs
    JUMP GameLoop
LED3: LOADI &B000111
    OUT LEDs
    JUMP GameLoop
LED2: LOADI &B000011
    OUT LEDs
    JUMP GameLoop
LED1: LOADI &B000001
    OUT LEDs
    JUMP GameLoop

; Evaluate numbers with targets
RoundOver:
    LOADI 0
    OUT LEDs

	; Check P1 target with score
    LOAD P1Guess
    SUB P1Target
    CALL GetResultCode
    STORE P1Result

	; Check P2 target with score
    LOAD P2Guess
    SUB P2Target
    CALL GetResultCode
    STORE P2Result

    ; Show results
    LOAD P1Result
    CALL ShiftLeft      
    OUT Hex1
    LOAD P2Result
    CALL ShiftLeft
    OUT Hex0

    ; Check for winner
    LOAD P1Result
    JZERO GameOver      
    LOAD P2Result
    JZERO GameOver      

    ; Tie-break countdown
    LOADI &B000111      
    OUT LEDs
    CALL Delay
    LOADI &B000011      
    OUT LEDs
    CALL Delay
    LOADI &B000001      
    OUT LEDs
    CALL Delay
    JUMP StartTimer     

; Display which player won
; '111111' for P1 win
; '222222' for P2 win
GameOver:
    ; Check if P1 won
    LOAD P1Result
    JNZ CheckP2Win
    LOADI 17        ; 17 decimal = 0x11
    OUT Hex1
	LOADI 1
	SHIFT 12
	ADDI  273		; 4369 decimal = 0x1111
	OUT Hex0
CheckP2Win:
    ; Check if P2 won
    LOAD P2Result
    JNZ WaitReset
    LOADI 34        ; 34 decimal = 0x22
    OUT Hex1
	LOADI 34
	SHIFT 8
	ADDI 34			; 8738 decimal = 0x2222
	OUT Hex0

; Wait to reset game
WaitReset:
	CALL FlashLeds
    IN Switches
    AND Mask9
    JNZ WaitReset       
WaitResetUp:
    IN Switches
    AND Mask9
    JZERO WaitResetUp    
    JUMP Init

; Helper subroutines
GetResultCode:
    JNEG IsLow
    JPOS IsHigh
    LOADI 0
    RETURN
IsHigh: 
    LOADI 10
    RETURN
IsLow:  
    LOADI 11
    RETURN

ShiftLeft:
    STORE ShiftTemp
    ADD ShiftTemp
    STORE ShiftTemp
    ADD ShiftTemp
    STORE ShiftTemp
    ADD ShiftTemp
    STORE ShiftTemp
    ADD ShiftTemp
    RETURN

ScaleTo99:
    STORE ScaleTemp
    LOADI 0
    STORE ScaleQuot
SLoop:
    LOAD ScaleTemp
    SUB Const41
    JNEG SDone
    STORE ScaleTemp
    LOAD ScaleQuot
    ADDI 1
    STORE ScaleQuot
    JUMP SLoop
SDone:
    LOAD ScaleQuot
    RETURN

PackDecimal:
    STORE PackTemp
    LOADI 0
    STORE PackTens
PLoop:
    LOAD PackTemp
    SUB Const10
    JNEG PDone
    STORE PackTemp
    LOAD PackTens
    ADDI 1
    STORE PackTens
    JUMP PLoop
PDone:
    LOAD PackTens
    STORE ShiftTemp
    CALL Mul15ShiftTemp
    ADD PackTemp
    RETURN

Mul15ShiftTemp:
	LOAD ShiftTemp
	SHIFT &H4
    SUB ShiftTemp
    RETURN

Delay:
	OUT    Timer
DelayLoop:
	IN     Timer
	ADDI   -15
	JNEG   DelayLoop
	RETURN

FlashDelay:
	OUT    Timer
FlashDelayLoop:
	IN     Timer
	ADDI   -5
	JNEG   FlashDelayLoop
	RETURN

FlashLeds:
	LOAD MaskLedsOn
    OUT  LEDs
    CALL FlashDelay
    LOAD MaskLedsOff
    OUT  LEDs
    CALL FlashDelay
    RETURN

; Variables
P1Target:  DW 0
P2Target:  DW 0
P1Guess:   DW 0
P2Guess:   DW 0
P1Result:  DW 0
P2Result:  DW 0
TimerVal:  DW 0
ScaleTemp: DW 0
ScaleQuot: DW 0
PackTemp:  DW 0
PackTens:  DW 0
ShiftTemp: DW 0

; Constants
Const10:   DW 10
Const20:   DW 20
Const30:   DW 30
Const40:   DW 40
Const41:   DW 41
Const50:   DW 50
Mask7:     DW &B0010000000 
Mask8:     DW &B0100000000 
Mask9:     DW &B1000000000 
MaskLedsOn: DW &B101010101
MaskLedsOff:     DW &B000000000

; Peripherals
CH0:       EQU &HC0
CH7:       EQU &HC7
Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
Hex0:      EQU 004
Hex1:      EQU 005
