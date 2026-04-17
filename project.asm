; PotGuess_Championship_Edition.asm
; SW8: P1 Lock | SW7: P2 Lock | SW9: Master Start/Reset
; ---------------------------------------------------------------
ORG 0

Init:
    LOADI 0
    OUT Hex0
    OUT Hex1
    OUT LEDs

; --- PHASE 1: Player 1 Sets Target ---
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

; --- PHASE 2: Player 2 Sets Target ---
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

; --- PHASE 3: Master Ready Check ---
WaitMasterStart:
    IN Switches
    AND Mask9
    JZERO WaitMasterStart 

; --- PHASE 4: The Game Round ---
StartTimer:
    LOADI 0
    OUT Timer

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

    ; LED Countdown Logic (Original)
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

; --- PHASE 5: Evaluation ---
RoundOver:
    LOADI 0
    OUT LEDs
    
    LOAD P1Guess
    SUB P1Target
    CALL GetResultCode
    STORE P1Result

    LOAD P2Guess
    SUB P2Target
    CALL GetResultCode
    STORE P2Result

    ; Show Standard Results first (A/b/0)
    LOAD P1Result
    CALL ShiftLeft      
    OUT Hex1
    LOAD P2Result
    CALL ShiftLeft
    OUT Hex0

    ; Check for Winner
    LOAD P1Result
    JZERO GameOver      
    LOAD P2Result
    JZERO GameOver      

    ; TIE-BREAK COUNTDOWN
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

; --- PHASE 6: Victory Display ---
GameOver:
    ; Check if P1 won
    LOAD P1Result
    JNZ CheckP2Win
    LOADI 17        ; 17 decimal = 0x11, shows "11"
    OUT Hex1
	LOADI 1
	SHIFT 12
	ADDI  273
	OUT Hex0
CheckP2Win:
    ; Check if P2 won
    LOAD P2Result
    JNZ WaitReset
    LOADI 34        ; 34 decimal = 0x22, shows "22"
    OUT Hex1
	LOADI 34
	SHIFT 8
	ADDI 34
	OUT Hex0

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

; --- SUBROUTINES ---

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

; --- DATA ---
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

CH0:       EQU &HC0
CH7:       EQU &HC7
Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
Hex0:      EQU 004
Hex1:      EQU 005