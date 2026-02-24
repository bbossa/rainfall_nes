;*****************************************************************
; Generic NES library
;*****************************************************************

;*****************************************************************
; Define NES control register values
;*****************************************************************

; Define PPU Registers
PPU_CONTROL = $2000 		; PPU Control Register 1 (Write)
PPU_MASK = $2001 			; PPU Control Register 2 (Write)
PPU_STATUS = $2002			; PPU Status Register (Read)
PPU_SPRRAM_ADDRESS = $2003 	; PPU SPR-RAM Address Register (Write)
PPU_SPRRAM_IO = $2004 		; PPU SPR-RAM I/O Register (Write)
PPU_VRAM_ADDRESS1 = $2005 	; PPU VRAM Address Register 1 (Write)
PPU_VRAM_ADDRESS2 = $2006 	; PPU VRAM Address Register 2 (Write)
PPU_VRAM_IO = $2007 		; VRAM I/O Register (Read/Write)
SPRITE_DMA = $4014 			; Sprite DMA Register

; Define PPU control register masks
NT_2000 = $00 ; nametable location
NT_2400 = $01
NT_2800 = $02
NT_2C00 = $03

VRAM_DOWN = $04 ; increment VRAM pointer by row

OBJ_0000 = $00 
OBJ_1000 = $08
OBJ_8X16 = $20

BG_0000 = $00 ; 
BG_1000 = $10

VBLANK_NMI = $80 ; enable NMI

BG_OFF = $00 ; turn background off
BG_CLIP = $08 ; clip background
BG_ON = $0A ; turn background on

OBJ_OFF = $00 ; turn objects off
OBJ_CLIP = $10 ; clip objects
OBJ_ON = $14 ; turn objects on

OBJ_PAL_1 = $00 ; Sprite palette 1
OBJ_PAL_2 = $01 ; Sprite palette 2
OBJ_PAL_3 = $02 ; Sprite palette 3
OBJ_PAL_4 = $03 ; Sprite palette 4

OBJ_FG = $00 	; Sprite on foreground 
OBJ_BG = $20	; Sprite on background

; Useful PPU memory addresses
NAME_TABLE_0_ADDRESS		= $2000
ATTRIBUTE_TABLE_0_ADDRESS	= $23C0
NAME_TABLE_1_ADDRESS		= $2400
ATTRIBUTE_TABLE_1_ADDRESS	= $27C0

; Define APU Registers
APU_DM_CONTROL = $4010 		; APU Delta Modulation Control Register (Write)
APU_CLOCK = $4015 			; APU Sound/Vertical Clock Signal Register (Read/Write)

; Joystick/Controller values
JOYPAD1 = $4016 			; Joypad 1 (Read/Write)
JOYPAD2 = $4017 			; Joypad 2 (Read/Write)

; Gamepad bit values
PAD_A      = $01
PAD_B      = $02
PAD_SELECT = $04
PAD_START  = $08
PAD_U      = $10
PAD_D      = $20
PAD_L      = $40
PAD_R      = $80

;*****************************************************************
; 6502 Zero Page Memory (256 bytes)
;*****************************************************************

.segment "ZEROPAGE"

;; A Zero-page segment is the first 256 bytes of memory and is accessible in code by using
;; a single-byte (zero-page) instruction. This is where to declare variables
;; This segment is stored in RAM and have a quicker access than 2 bytes adress


;; Instruction .res reserve n byte of storage
nmi_ready:		.res 1 ; set to 1 to push a PPU frame update,
					   ;        2 to turn rendering off next NMI
ppu_ctl0:		.res 1 ; PPU Control Register Value -> PPU CONTROL
ppu_ctl1:		.res 1 ; PPU Control Register Value -> PPU MASK

gamepad:		.res 1 ; stores the current gamepad values

text_address:	.res 2 ; set to the address of the text to write

.include "macros.asm"

;*****************************************************************
; wait_frame: waits until the next NMI occurs
;*****************************************************************
.segment "CODE"
.proc wait_frame
	inc nmi_ready       ; Add 1 ton nmi_ready 
@loop:
	lda nmi_ready       ; Load nmi_ready
	bne @loop           ; Branch till nmi_ready is equal to 0
	rts                 ; Exit subroutine
.endproc

;*****************************************************************
; ppu_update: waits until next NMI, turns rendering on (if not already), uploads OAM, palette, and nametable update to PPU
;*****************************************************************
.segment "CODE"
.proc ppu_update
	lda ppu_ctl0        ; Load adress ppu_ctl0 in ZP
	ora #VBLANK_NMI     ; OR mask with %10000000 
	sta ppu_ctl0        ; Store result in ppu_ctl0 in ZP
	sta PPU_CONTROL

	lda ppu_ctl1        ; Load adress ppu_ctl1 in ZP
	ora #OBJ_ON|BG_ON   ; OR mask with 00010100 | 00001010 -> 00011100
	sta ppu_ctl1        ; Store result in ppu_ctl1 in ZP
	jsr wait_frame      ; Wait frame
	rts                 ; Exit subroutine
.endproc

;*****************************************************************
; ppu_off: waits until next NMI, turns rendering off (now safe to write PPU directly via PPU_VRAM_IO)
;*****************************************************************
.segment "CODE"
.proc ppu_off
	jsr wait_frame      ; Wait frame
	lda ppu_ctl0        ; Load adress ppu_ctl0 in ZP
	and #%01111111      ; AND mask (clear bit 7)
	sta ppu_ctl0        ; Store result in ppu_ctl0 in ZP
	sta PPU_CONTROL     ; Set PPU Control 

	lda ppu_ctl1        ; Load adress ppu_ctl1 in ZP
	and #%11100001      ; AND mask (clear bit 4,3,2,1)
	sta ppu_ctl1        ; Store result in ppu_ctl1 in ZP
	sta PPU_MASK        ; Set PPU MASK
	rts                 ; Exit subroutine
.endproc

;*****************************************************************
; clear_nametable: clears the first name table
;*****************************************************************
.segment "CODE"
.proc clear_nametable
 	lda PPU_STATUS          ; reset address latch
    ; set PPU address to $2000
 	lda #$20                ; Higher adress
 	sta PPU_VRAM_ADDRESS2   ; Set into VRAM adress
 	lda #$00                ; Lower adress
 	sta PPU_VRAM_ADDRESS2   ; Set into VRAM adress

 	; empty nametable
 	lda #0                  ; Load A with 0
 	ldy #30                 ; Load Y with 30 - clear 30 rows
 	rowloop:
 		ldx #32              ; Load X with 32 - 32 columns
 		columnloop:
 			sta PPU_VRAM_IO ; Store A to PPU_VRAM_IO
 			dex             ; Decrement X
 			bne columnloop  ; Branch Not Equal - Branch if Z flag is clear (0) - Flag is set when X is equal to 0
 		dey                 ; Decrement Y
 		bne rowloop         ; Branch Not Equal - Branch if Z flag is clear (0) - Flag is set when Y is equal to 0

 	; empty attribute table
 	ldx #64                 ; Load W with 64 - attribute table is 64 bytes
 	loop:
 		sta PPU_VRAM_IO     ; Store A to PPU_VRAM_IO
 		dex                 ; Decremetn X
 		bne loop            ; Branch Not Equal - Branch if Z flag is clear (0) - Flag is set when X is equal to 0
 	rts                     ; Exit subroutine
 .endproc


;*****************************************************************
; gamepad_poll: this reads the gamepad state into the variable labelled "gamepad"
; This only reads the first gamepad, and also if DPCM samples are played they can
; conflict with gamepad reading, which may give incorrect results.
;*****************************************************************
; $4016 (JOYPAD1) can be used in Read / Write mode
; Write mode
; 7654 3210
; ---- -EES
; ---- -||+ -> Controller port latch bit
; ---- -++- -> Expansion port latch bits
; Write 1 to $4016 to signal the controller to poll its input. Write 0 to $4016 to finish the poll
;
; Read Mode
; 7654 3210
; ---- -MES
; ---- -||+ -> Primary controller status bit
; ---- -|+- -> Expansion controller status bit (Famicom)
; ---- -+-- -> Microphone status bit (Famicom, $4016 only)
;*****************************************************************
.segment "CODE"
.proc gamepad_poll
	; strobe the gamepad to latch current button state (set 1 thens et 0 to bit 0 of $4016)
	lda #1              ; Load A with 1
	sta JOYPAD1         ; Store A into JOYPAD1 adress
	lda #0              ; Load A with 0
	sta JOYPAD1         ; Store A into JOYPAD1 adress
    ; Now controller A can be read to get input

	; read 8 bytes from the interface at $4016 (each bit per pool)
	ldx #8              ; Load X with 8
loop:
	pha                 ; Store A in stack
	lda JOYPAD1         ; Load A with JOYPAD1 inputs
	; combine low two bits and store in carry bit
	and #%00000011      ; AND to only get two lower bit -> Store into A
	cmp #%00000001      ; Comparison with mask 00000001 -> If A >= M i.e. 11 or 10 or 01 -> carry bit is 1, otherwise 0
	pla                 ; Pull A from stask
	; rotate carry into gamepad variable
	ror a               ; Shift A to left. Bit 7 is set with carry flag.
	dex                 ; Decrement X
	bne loop            ; Branch Not Equal - Branch if Z flag is clear (0) - Flag is set when X is equal to 0

	sta gamepad         ; Store A (which contains all button status) to gamepad adress
	cmp #0
	bne :+
		lda #0
		sta flaginput
	:
	rts                 ; Exit subroutine
.endproc

;*****************************************************************
; write_text: This writes a section of text to the screen
; text_address - points to the text to write to the screen
; PPU address has been set
;*****************************************************************
.segment "CODE"
.proc write_text
	ldy #0                  ; Load Y with 0
loop:
	lda (text_address),y    ; Load A with current text adress (text_adress + Y)
	beq exit                ; Branch on equal exit when we encounter a zero in the text
	sta PPU_VRAM_IO         ; write the byte to video memory
	iny                     ; Increment Y
	jmp loop                ; Infinite loop
exit:
	rts                     ; Exit subroutine
.endproc

;*****************************************************************
; randomize: Get a random value from the current SEED values
;*****************************************************************

.segment "ZEROPAGE"

SEED0: .res 2
SEED2: .res 2

; simple shift based random number
.segment "CODE"
.proc randomize
	lda SEED0
	lsr
	rol SEED0+1
	bcc @noeor
	eor #$B4
@noeor:
	sta SEED0
	eor SEED0+1
	rts
.endproc

; Linear Frequency random numbers
; result in a (lo) and y (hi)
.proc rand
	jsr rand64k	; Factors of 65536: 3 5 17 257
	jsr rand32k ; Factors of 32767; 7 31 151
	lda SEED0+1	; combine other seed values
	eor SEED2+1
	tay	; save hi byte
	lda SEED0	; mix up lowbytes of SEED0
	eor SEED2	; and SEED2 to combine both
	rts
.endproc

.proc rand64k
	lda SEED0+1
	asl
	asl
	eor SEED0+1
	asl
	eor SEED0+1
	asl
	asl
	eor SEED0+1
	asl
	rol SEED0	; shift this left, "random" bit comes from low
	rol SEED0+1
	rts
.endproc

.proc rand32k
	lda SEED2+1
	asl
	eor SEED2+1
	asl
	asl
	ror SEED2	; shift this right, random bit comes from high
	rol SEED2+1
	rts
.endproc

;*****************************************************************
; collision_test: Check whether two objects have hit each other
; Returns: Carry flag set if objects have hit each other
;*****************************************************************

.segment "ZEROPAGE"

cx1:	.res 1 ; object 1 X position
cy1:	.res 1 ; object 1 Y position
cw1:	.res 1 ; object 1 width
ch1:	.res 1 ; object 1 height

cx2:	.res 1 ; object 2 X position
cy2:	.res 1 ; object 2 Y position
cw2:	.res 1 ; object 2 width
ch2:	.res 1 ; object 2 height

.segment "CODE"

.proc collision_test
	clc
	lda cx1 ; get object 1 x
	adc cw1 ; add object 1 width
	BCC :+
		clc
		lda #$FF
	:
	cmp cx2 ; is object 2 to the right of object 1 plus it's width?
	bcc @exit
	clc
	lda cx2 ; get object 2 x
	adc cw2 ; add object 2 width
	cmp cx1 ; is object 2 to the left of object 1?
	bcc @exit
	lda cy1 ; get object 1 y
	adc ch1 ; add object 1 height
	cmp cy2 ; is object 2 below object 1 plus it's height?
	bcc @exit
	clc
	lda cy2 ; get object 2 y
	adc ch2 ; add object 2 height
	cmp cy1 ; is object 2 above object 1?
	bcc @exit

	sec ; we have hit, set carry flag and exit
	rts
@exit:
	clc ; clear carry flag and exit
	rts
.endproc

;*****************************************************************
;  0-99 Decimal to digit conversion
;  A = number to convert
; Outputs:
; X = decimal tens
; A = decimal ones
;*****************************************************************
.segment "CODE"

.proc dec99_to_bytes
    ldx    #0
    cmp    #50                   ; A = 0-99
    bcc    try20
    sbc    #50
    ldx    #5
    bne    try20                ; always branch

div20:
    inx
    inx
    sbc    #20

try20:
    cmp    #20
    bcs    div20

try10:
    cmp    #10
    bcc    @finished
    sbc    #10
    inx

@finished:
	; X = decimal tens
	; A = decimal ones

	rts
.endproc

.proc clear_sprites
	; place all sprites offscreen at Y=255
	lda #255
	ldx #0
clear_oam:
	sta oam,x
	inx
	inx
	inx
	inx
	bne clear_oam

	rts
.endproc