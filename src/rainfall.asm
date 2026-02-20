;*****************************************************************
; NES GAME : Rain Fall
;*****************************************************************


;*****************************************************************
; General considerations
; .segment indicates to compiler to set following instruction to be set into the specific memory area (defined in memory.cfg)
;
;         RAM areas                        ROM areas
; +---------------------------------+    +---------------------------------+ 
; |   Zero-page ($0000 - $00FF)     |    |                                 |
; +---------------------------------+    |        Lower ROM bank 16K       |
; | Stack spaces ($1000 - $01FF)    |    |         ($8000 - $BFFF)         |
; +---------------------------------+    |                                 |
; | OAM sprite data ($0200 - $02FF) +    +---------------------------------+
; +---------------------------------+    |                                 |
; | Remainder of RAM ($0300 -$07FF) |    |        Upper ROM bank 16K       |
; |                                 |    |         ($C000 - $FFFF)         |
; |                                 |    |                                 |
; +---------------------------------+    +---------------------------------+
;*****************************************************************

;*****************************************************************
; Define NES cartridge Header
;*****************************************************************

.segment "HEADER"
INES_MAPPER = 0 ; 0 = NROM
INES_MIRROR = 0 ; 0 = horizontal mirroring, 1 = vertical mirroring
INES_SRAM   = 0 ; 1 = battery backed SRAM at $6000-7FFF

.byte 'N', 'E', 'S', $1A ; ID
.byte $02 ; 16k PRG bank count
.byte $01 ; 8k CHR bank count
.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << 4)
.byte (INES_MAPPER & %11110000)
.byte $0
.byte $1 	; 0 - NTSC, 1 - PAL
.byte $0, $0, $0, $0, $0, $0 ; padding

;*****************************************************************
; Import both the background and sprite character sets
;*****************************************************************

.segment "TILES"
.incbin "rainfall.chr"

;*****************************************************************
; Define NES interrupt vectors : REQUIRED
;*****************************************************************

.segment "VECTORS"

.word nmi 		; Non-Maskable Interrupt - called when the screen has been drawn and the raster is moving to the top of the screen (also known as a vBlank)
.word reset 	; The starting point (or reset point) of your game
.word irq 		; The interrupt indicating a clock tick has occurred

;*****************************************************************
; 6502 Zero Page Memory (256 bytes)
;*****************************************************************

.segment "ZEROPAGE"

time: .res 1
lasttime: .res 1
level: .res 1
animate: .res 1
enemydata: .res 10
heardata: .res 2
boltdata: .res 1
enemycooldown: .res 1
heartcooldown: .res 1
boltcooldown: .res 1
temp: .res 10
bottom_line: .res 1

;*****************************************************************
; Sprite Object Attirbute Memory Data area
; copied to VRAM in NMI routine
;*****************************************************************

.segment "OAM"
;; Reservation of 256 byte for Sprites
; Each sprites need 4 bytes (64 sprites in total) to be defined
oam: .res 256	; sprite OAM data

;*****************************************************************
; Include NES Function Library
;*****************************************************************

.include "neslib.asm"

;*****************************************************************
; Remainder of normal RAM area
;*****************************************************************

.segment "BSS"
palette: .res 32 ; current palette buffer

;*****************************************************************
; Main application entry point for starup/reset
;*****************************************************************

.segment "CODE"
.proc reset
	sei					; Disable interrupts
	cld					; Disable decimal mode

	;; Disbale video and sound during initialization to ensure no visual or audible artifact are geenrated during this phase.
	lda #$0				; Load A with value 0
	;*****************************************************************
	; PPU CONTROL
	; 7654 3210
	; VPHB SINN
	; |||| ||++ -> Base nametable address (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
	; |||| |+-- -> VRAM address increment per CPU read/write of PPUDATA  (0: add 1, going across; 1: add 32, going down)
	; |||| +--- -> Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000; ignored in 8x16 mode)
	; |||+ ---- ->  Background pattern table address (0: $0000; 1: $1000)
	; ||+- ---- -> Sprite size (0: 8x8 pixels; 1: 8x16 pixels)
	; |+-- ---- -> PPU master/slave select (0: read backdrop from EXT pins; 1: output color on EXT pins) - Bit 6 of PPUCTRL should never be set on stock consoles because it may damage the PPU. 
	; +--- ---- -> Vblank NMI enable (0: off, 1: on)
	;*****************************************************************
	sta PPU_CONTROL		; disable NMI

	;*****************************************************************
	; PPU MASK
	; 7654 3210
	; BGRs bMmG
	; |||| |||+ -> Greyscale (0: normal color, 1: greyscale)
	; |||| ||+- -> 1: Show background in leftmost 8 pixels of screen, 0: Hide
	; |||| |+-- -> 1: Show sprites in leftmost 8 pixels of screen, 0: Hide
	; |||| +--- -> 1: Enable background rendering
	; |||+ ---- -> 1: Enable sprite rendering
	; ||+- ---- -> Emphasize red (green on PAL/Dendy)
	; |+-- ---- -> Emphasize green (red on PAL/Dendy)
	; +--- ---- -> Emphasize blue
	;*****************************************************************
	sta PPU_MASK		; disable rendering

	;*****************************************************************
	; APU DMC
	; 7654 3210
	; IL-- RRRR
	; ||-- ++++ -> Rate index (c.f. lower)
	; |+-- ---- -> Loop flag
	; +--- ---- -> IRQ enabled flag. If clear, the interrupt flag is cleared. 
	;
	; Rate index : 0000 NTSC PAL
	; $0 428 398
	; $1 380 354
	; $2 340 316
	; $3 320 298
	; $4 286 276
	; $5 254 236
	; $6 226 210
	; $7 214 198
	; $8 190 176
	; $9 160 148
	; $A 142 132
	; $B 128 118
	; $C 106, 98
	; $D 84 78
	; $E 72 66
	; $F 54 50
	; The rate determines for how many CPU cycles happen between changes in the output level during automatic delta-encoded sample playback.
	;*****************************************************************
	sta APU_DM_CONTROL	; disable DMC IRQ

	;; Register $4017 in write mode control the frame counter
	;; Set to $40 (64 or b01000000) -> Interupt inhibit flag cleared
	lda #$40			; Load A with value $40 (64)
	sta JOYPAD2			; disable APU frame IRQ
	
	ldx #$FF			; Load X with value $FF (255)
	txs					; Transfer X to stack pointer - Initialise stack

;*****************************************************************
; PPU STATUS flags
; 7654 3210
; |||+ ++++ -> 2C05 PPU identifier
; ||+- ---- -> Sprite overflow flag
; |+-- ---- -> Sprite 0 hit flag
; +--- ---- -> Vblank flag, cleared on read
; The vblank flag is set at the start of vblank (scanline 241, dot 1)
; If the vblank flag is not cleared by reading, it will be cleared automatically on dot 1 of the prerender scanline
;*****************************************************************
	; wait for first vBlank (i.e. the first screen has been drawn)
	bit PPU_STATUS		; Compare bit value : -> N (bit 7) is set to 1 if VBLANK
wait_vblank:
	bit PPU_STATUS		; Compare bit value : -> N (bit 7) is set to 1 if VBLANK
	bpl wait_vblank		; Branch if Positive (Bit 7 equal to 0) -> in case of VBLANK the code continue.

; clear all RAM to 0
	lda #0				; Load A with 0
	ldx #0				; Load X with 0
clear_ram:
	sta $0000,x			; Store value of A (0) into Adress $0000 (0) + X
	sta $0100,x			; Store value of A (0) into Adress $0100 (256) + X
	sta $0200,x			; Store value of A (0) into Adress $0200 (512) + X
	sta $0300,x			; Store value of A (0) into Adress $0300 (768) + X
	sta $0400,x			; Store value of A (0) into Adress $0400 (1024) + X
	sta $0500,x			; Store value of A (0) into Adress $0500 (1024) + X
	sta $0600,x			; Store value of A (0) into Adress $0600 (1280) + X
	sta $0700,x			; Store value of A (0) into Adress $0700 (1792) + X
	inx					; Increment X
	bne clear_ram		; branch on not equal (Bit 6 clear) (loop till X is equal to 0. When INX set X to 0, bit 6 is set and branch stop)

	; PLace all sprites offscreen
	; OAM contains all 64 sprites. Each sprites need 4 bytes. The first byte control the Y position. At 255 sprites is off screen
	; Sprites uses 4 bytes :
	; Byte 0 : Y position (Y of the top left corner of the 8x8 tile).Due to scan line usage, draw at Y+1. Rrange 239-255 is offscreen. 255 is usually used to defined unused sprites
	; Byte 1 : index number of the tiles patterns
	; byte 2 : Sprite attributes. Bits 0-1 defines palette. Bit 5 defines if draw in front of the BG (0) or behind (1). Bit 6 flip horizontally the sprite. Bit 7 flip vertically the sprite
	; Byte 3 : X position  (top left corner of the 8x8 tiles)
	lda #255			; Load A with 255 
	ldx #0				; Load X with 0
clear_oam:
	sta oam,x			; Store A with value $FF at oam adress + X
	inx					; Increment X
	inx					; Increment X
	inx					; Increment X
	inx					; Increment X (+4 each loop)
	bne clear_oam 		; branch on not equal (zero clear) (loop till X is equal to 0)

; wait for second vBlank (refer to first vBlank loop)
wait_vblank2:
	bit PPU_STATUS		; Compare bit value --> here check bit 7 & 6 of PPU STATUS
	bpl wait_vblank2	; Branch if Positive (loop if bit 7 is equal to 0)

	; NES is initialized and ready to begin
	; - enable the NMI for graphical updates and jump to our main program
	lda #%10001000
	sta PPU_CONTROL

	; Jump to main loop
	jmp main
.endproc

;*****************************************************************
; NMI Routine - called every vBlank
;*****************************************************************

.segment "CODE"
.proc nmi
	; save registers (to prevent corruption)
	pha		; Push A to stack
	txa		; Transfer X to A
	pha		; Push A to stack (X)
	tya		; Transfert Y to A
	pha		; Push A to stack (Y)

	; incrememt our time tick counter
	inc time

	lda nmi_ready
	;; BNE :+ (Branch Not Equal - If the bit 1 (Z) is not set then jump to next unlabbeled section (:+))
	;; If nmi_ready is not equal to 0, skip the following instruction : jmp ppu_update_end, otherwise perform the instruction
	bne :+ ; nmi_ready == 0 not ready to update PPU
		jmp ppu_update_end
	:

	;; Compare A (which contains nmi_ready) to 2. If not, jump to 'cont_render section'
	cmp #2 ; nmi_ready == 2 turns rendering off
	bne cont_render

	;; This part is only run if nmi_ready is equal to 2
	lda #%00000000			; Load 0 in decimal (PPU mask)
	sta PPU_MASK			; Set PPU mask to 0
	ldx #0					; Set X to 0
	stx nmi_ready			; Set nm_ready to 0
	jmp ppu_update_end		; jump to end update section

	;; This section is run only if nmi_ready is not equal to 0 or equal to 2 (usually 1)
cont_render:
	; transfer sprite OAM data using DMA
	ldx #0						; Set 0 to X
	stx PPU_SPRRAM_ADDRESS		; Set PPPU SRAM address to X (0)
	lda #>oam					; TBD
	sta SPRITE_DMA				; Store A to this adress

	; transfer current palette to PPU
	lda #%10001000 				; set horizontal nametable increment (PPU mask TBD)
	sta PPU_CONTROL				; Set PPU Control with previous byte
	lda PPU_STATUS				; Get PPU Status (latch)
	; set PPU address to $3F00
	lda #$3F 					; higher adress value with A
	sta PPU_VRAM_ADDRESS2		; Set higher adress value
	stx PPU_VRAM_ADDRESS2		; Set lower adress value with X (previously set to 0)

	; transfer the 32 bytes to VRAM
	ldx #0 						; Set 0 to X (could be remove)
loop:
	lda palette, x				; Store A with adresse palette + X
	sta PPU_VRAM_IO				; Store into PPU_VRAM_Adress
	inx							; increment X
	cpx #32						; Compare to 32 (is lower than 32, C and Z flag will be set to 0)
	bcc loop					; Branch on Carry Clear - Jump to loop section until Carry Flag (C) is set (when X is equal or hiher than 32)

	; Disable scrolling
	lda #0
	sta PPU_VRAM_ADDRESS1
	sta PPU_VRAM_ADDRESS1

	lda ppu_ctl0
	sta PPU_CONTROL
	lda ppu_ctl1
	sta PPU_MASK


	; flag PPU update complete
	ldx #0						; Set X to 0
	stx nmi_ready				; Set nmi_ready to 0

ppu_update_end:

	; restore registers and return
	pla		; Pull A from stack (Y)
	tay		; Transfert A to Y 
	pla		; Pull A from stack (X)
	tax		; Transfert A to X
	pla		; Pull A from stack
	rti		; Return from this subroutine caused by an interrupt
.endproc

;*****************************************************************
; IRQ Clock Interrupt Routine
;*****************************************************************

.segment "CODE"
irq:
	rti		; Return from this subroutine caused by an interrupt

;*****************************************************************
; Main application logic section includes the game loop
;*****************************************************************
 .segment "CODE"
 .proc main
 	; main application - rendering is currently off

	; initialize palette table
 	ldx #0					; Load X with 0
paletteloop:
	lda default_palette, x	; Load A with adress default_palette + X
	sta palette, x			; Store A in adress palette + X
	inx						; Increment X
	cpx #32					; Compare with value 32
	bcc paletteloop			; Branch on Carry Clear - If X is lower than 32, the Carry flag is not set, branch occurs.

	; Draw the title screen
	jsr display_title_screen

	; Set game settings (TBD)
	lda #VBLANK_NMI|BG_0000|OBJ_1000		; Should be complex number via combinaison of different mask (or)
	sta ppu_ctl0
	lda #BG_ON|OBJ_ON
	sta ppu_ctl1

	; Wait until the screen has been drawn
	jsr ppu_update

titleloop:
	; Poll gamepad
	jsr gamepad_poll
	;; Game pad is store as:
	;	7654 3210
	;   Right - Left - Down - Up - Start - Select - B - A
	lda gamepad				; Load A with gamepad input ()
	and #PAD_A|PAD_START|PAD_L|PAD_R   	; i.e. AND #%00001001
	beq titleloop			; Branch on Equal - Branch is zero flag is set - If A or Start is not presses, then result is 0 (any other button can be pressed)

	; set our random seed based on the time counter since the splash screen was displayed
	lda time				; Load A with value of time
	sta SEED0				; Store time value inbto first seed
	lda time+1				; Get higher byte
	sta SEED0+1				; Store into high byte of seed0
	jsr randomize			; Call randomize routine
	sbc time+1				; Substract with carry
	sta SEED2   			; Store into seed2
	jsr randomize			; Call randomize routine
	sbc time				; subtract wih carry
	sta SEED2+1				; Store into high byte of seed2

	; set up ready for a new game
	lda #1					; Load A with value 1
	sta level				; Store into level (level 1 for difficulty)
	jsr setup_level			; Setup level

	; draw the game screen
	jsr display_game_screen

	; display the player's cloud
	; set the Y position (byte 0) of all six parts of the player cloud
	; A sprite is defined with 4 bytes 0 1 2 3 - Y, Index, Attributes, X 
	lda #196 		; Define Y position (pixel)
	sta oam			; Store into sprite 1 (top left)
	sta oam+4 		; Store into sprite 2 (top middle)
	sta oam+8 		; Store into sprite 3 (top right)
	lda #204		; 196 + 8 (increase position by sprite height)
	sta oam+12		; Store into sprite 4 (bottom left)
	sta oam+16		; Store into sprite 5 (bottom middle)
	sta oam+20		; Store into sprite 6 (bottom right)

	; Set index number (byte 1) of the sprite pattern (which sprite to use in CHR)
	ldx #0			; First index: 0
	stx oam+1		; Store into sprite 1 (top left) (byte 0 + 1)
	inx				; increment X (index 1)
	stx oam+5		; Store into sprite 2 (top middle)
	inx				; increment X (index 2)
	stx oam+9		; Store into sprite 3 (top right)
	inx				; increment X (index 3)
	stx oam+13		; Store into sprite 4 (bottom left)
	inx				; increment X (index 4)
	stx oam+17		; Store into sprite 5 (bottom middle)
	inx				; increment X (index 5)
	stx oam+21		; Store into sprite 6 (bottom right)

	; set the sprite attributes (byte 2)
	lda #%00000000	; Load A with 0 mask
	sta oam+2		; Store into sprite 1 (top left) (byte 0 + 2)
	sta oam+6		; Store into sprite 2 (top middle)
	sta oam+10		; Store into sprite 3 (top right)
	sta oam+14		; Store into sprite 4 (bottom left)
	sta oam+18		; Store into sprite 5 (bottom middle)
	sta oam+22		; Store into sprite 6 (bottom right)

	; set the X position (byte 3)  of all six parts of the player cloud
	; middle is around 120 : 112 <- 120 -> 128
	lda #112		; Load A with left sprite position (120-8)
	sta oam+3		; Store into sprite 1 (top left) (byte 0 + 3)
	sta oam+15		; Store into sprite 4 (bottom left)
	lda #120 		; Load A with middle position (120)
	sta oam+7		; Store into sprite 2 (top middle)
	sta oam+19		; Store into sprite 5 (bottom middle)
	lda #128 		; Load A with right sprite position (120+8)
	sta oam+11		; Store into sprite 3 (top right)
	sta oam+23		; Store into sprite 6 (bottom right)

	; Draw sprites
	jsr ppu_update


mainloop:
	; Load current time (based on number of drame displayed - 60 for NTSC and 50 for PAL)
	lda time

	; ensure the time has actually changed
	cmp lasttime		; CMP withn returne zero flag set if last time equal time, carry flag is set if time is greater or equal to lasttime, zero bit is set if time is lower than lasttime
	beq mainloop		; Branch on Equal - If the zero flag is set, BEQ branches -> till time equal lastime, branch.

	; time has changed update the lasttime value
	sta lasttime		; Copyr current time to lasttime

	; Check user input
	jsr player_actions

	; Spawn and move ennemies
	jsr spawn_enemies
	jsr move_enemies

	; Spawn and move powerup
	jsr spawn_heart
	jsr move_heart
	jsr spawn_bolt
	jsr move_bolt

	; ensure our changes are rendered
 	lda #1
 	sta nmi_ready

	; Main loop
	jmp mainloop

 .endproc

;*****************************************************************
; Check for the game controller, move the player
;*****************************************************************
.segment "CODE"
.proc player_actions
	; Poll gamepad
	jsr gamepad_poll
	lda gamepad 				; Load A with Pad A buttons status
	and #PAD_L 					; AND with mask PAD_L (does left pressed)
	beq not_gamepad_left		; Branch if Equal - zero flag is set -> means left not pressed
		; game pad has been pressed left
		lda oam + 3 			; get current x of cloud (sprite 0 - byte 3)
		cmp #0 					; Comparison with 0 (mean cloud touch the left border)
		beq not_gamepad_left	; Branch if equal - Zero flag is set -> comparison is true don't move
		; subtract 4 from the ship position
		sec 					; Set the carry flag to one.
		sbc #4 					; Subtract with Carry A,Z,C,N = A-M-(1-C)
		; update the six sprites that make up the cloud
		; S1 S2 S3
		; S4 S5 S6
		sta oam + 3 			; sprite 1
		sta oam + 15 			; sprite 4
		clc 					; Set the carry flag to zero.
		adc #8 					; Add 8 (position of S2 / S5)
		sta oam + 7 			; sprite 2
		sta oam + 19 			; sprite 5
		clc 					; Set the carry flag to zero.
		adc #8 					; Add 8 (position of S2 / S5)
		sta oam + 11 			; sprite 3
		sta oam + 23 			; sprite 6
		
not_gamepad_left:
	lda gamepad
	and #PAD_R
	beq not_gamepad_right
		; gamepad has been pressed right
		lda oam + 3  			; get current X of cloud
		clc 					; Set the carry flag to zero.
		adc #22 				; allow with width of cloud
		cmp #254 				; Comparison with right border	
		beq not_gamepad_right 	; don't move
		lda oam + 3 			; get current X of cloud
		clc 					; Set the carry flag to zero.
		adc #4 					; Add with carry
		; update the six sprites that make up the cloud
		sta oam + 3 			; sprite 1
		sta oam + 15 			; sprite 4
		clc 					; Set the carry flag to zero.
		adc #8 					; Add with carry
		sta oam + 7 			; sprite 2
		sta oam + 19 			; sprite 5
		clc 					; Set the carry flag to zero.
		adc #8 					; Add with carry
		sta oam + 11 			; sprite 3
		sta oam + 23			; sprite 6
not_gamepad_right:
	rts
.endproc

;*****************************************************************
; Get setup for a new level
;*****************************************************************
.segment "CODE"

.proc setup_level 
	; CLear enmy data
	lda #0 				; Load A with 0
	ldx #0				; Load X with 0
@loop:
	sta enemydata,x		; Set 0 to enemy list (10 byte, one per enemy)
	inx					; Increment X
	cpx #10				; Compare to 10
	bne @loop			; Branch if Not Equal - If zero flag flag is clear branch -> CPX return zero flag set until X equal 10

	; set initial enemy cool down
	lda #50 			; Load A with 50 (time before to pop a new ennemy) (~1s)
	sta enemycooldown	; Store into cooldown adress

	; Clear powerup data (heart)
	lda #0				; Load A with 0
	ldx #0				; Load X with 0
@loop1:
	sta heardata,x		; Set 0 to heart list (3 byte, one per heart)
	inx					; Increment X
	cpx #2				; Branch if Not Equal - If zero flag flag is clear branch -> CPX return zero flag set until X equal 2
	bne @loop1

	; set initial heart powerup cooldown
	lda #100
	sta heartcooldown

	; Clear powerup data (bolt)
	lda #0				; Load A with 0
	ldx #0				; Load X with 0
@loop2:
	sta boltdata,x		; Set 0 to heart list (2 byte, one per heart)
	inx					; Increment X
	cpx #1				; Branch if Not Equal - If zero flag flag is clear branch -> CPX return zero flag set until X equal 1
	bne @loop2

	; set initial heart powerup cooldown
	lda #200
	sta boltcooldown

	; Set botom line Y
	lda #216
	sta bottom_line

	rts					; exit subroutine			
.endproc

;*****************************************************************
; Spawn ennemies
;*****************************************************************
.segment "CODE"

.proc spawn_enemies
	; Check if an ennemy can pop
	ldx enemycooldown 		; Load X with ennemy cooldown value
	dex						; Decrement X
	stx enemycooldown		; Store ennemy cooldown wit new value
	cpx #0					; Compare with 0
	beq :+					; Branch on equal - If zero flag is set branch - CPX return a zero flag when X equal 0 -> skip rts instruction
		rts					; Exit subroutine - not yet
	:

	; Spawn an ennemy based on psuedo RNG
	ldx #1 					; Load X with 1
	stx enemycooldown		; Store it into enemy cooldown -> to rpevent an error for the next call of this subroutine (next call will decrease cooldown by 1)

	lda level 				; Load A with current level
	clc						; Clear Carry flag
	adc #1 					; Add with Carry - increment by 1 the level
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	; +--> Result A is multiply by 4
	sta temp 				; Store A into temp adress - save our value
	jsr rand 				; Call rand routine - get next random value
	tay 					; transfer A into Y
	cpy temp				; Compare Y with temp (i.e. (lvl +1 ) * 4)
	; continue if random value less than our calculated value
	bcc :+ 					; Branch if Carry Clear - CPY set carry flag is Y >= M. If random value is less than our difficulty value an ennemy pop, other xise exit
		rts					; exit
	:

	; An ennemy pop - Reset cooldown value to intial value
	ldx #20 				; Load A with 20 - set new cool down period
	stx enemycooldown		; Store A into cooldown adress
	
	; Check if an ennemy can be displayed (max 10 ennemy on screen)
	ldy #0 					; Load Y with 0 - counter of enemy list

@loop:
	lda enemydata,y			; Load A with ennemy Y
	beq :+					; Branch on equal - If zero flag is set branch - Zero flag means ennmy is available (zero value). :+ means branch to next unlabeled tag
	iny 					; increment counter
	cpy #10					; Compare to 10 - max ennemy list
	bne @loop				; Branch if Not Equal - If zero flag flag is clear branch -> Y equal 10
		; did not find an enemy to use
		rts					; After the loop if no enenmy is available, exit
	:

	; mark the enemy as in use
	lda #1					; Load A with 1
	sta enemydata,y			; Store into ennemy byte

	; calculate first sprite oam position
	; Each enemy use 4 sprites (4 bytes eache). We must defines the first index of sprites in OAM based on enemy index:
	; Ennemy 0: 0
	; Ennemy 1: 16
	; ennemy 2: 32
	; ...
	; position on ennemy n: n * 16
	tya						; Transfert Y to A - Get current ennemy index
	; multiply by 16
	asl 					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x4) 
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x8)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x16)

	; The first 6 sprites are used by the player cloud. Each sprites takes 4 bytes. The position is then shifted by 24 (6 x 4)
	; Ennemy 0 -> position 24 in OAM; Ennemy 1 -> position 36 ...
	clc						; Clear Carry flag
	adc #24 				; Add with Carry - shift OAM position by 24
	tax						; Transfert A to X

	; now setup the enemy sprite
	; set the Y position (byte 0) of all four parts of the player ship
	lda #0					; Load A with 0 (top position Y)
	sta oam,x				; Sprite 1
	sta oam+4,x				; Sprite 2
	lda #8					; Load A with 8 (bottom line of sprites)
	sta oam+8,x				; sprite 3
	sta oam+12,x			; sprite 4
	
	; set the index number (byte 1) of the sprite pattern
	lda #6 					; Set Sprite index (6 in CHR)
	sta oam+1,x				; Sprite 1	
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+5,x				; Sprite 2
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+9,x				; Sprite 3
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+13,x			; Sprite 4
	
	; set the sprite attributes (byte 2)
	lda #%00000001			; Load A with 00000001 mask (palette 1)
	sta oam+2,x				; Sprite 1
	sta oam+6,x				; Sprite 2
	sta oam+10,x			; Sprite 3
	sta oam+14,x			; Sprite 4

	; set the X position (byte 3)  of all four parts of the player ship
	jsr rand				; Call Random routine
	and #%11110000			; AND to get only higher bits
	clc						; Carry clear
	adc #48					; Add with carry (+48)
	sta oam+3,x				; Sprite 1
	sta oam+11,x			; Sprite 3
	clc						; Carry clear
	adc #8					; Add with carry (+8)
	sta oam+7,x				; Sprite 2
	sta oam+15,x			; Sprite 4

	rts						; Exit
.endproc

;*****************************************************************
; Move ennemies downward
;*****************************************************************
.segment "CODE"

.proc move_enemies

	; setup for collision detection with player
	lda oam ; get cloud Y position
	clc
	adc #5
	sta cy1
	lda oam+3 ; get cloud x position
	sta cx1
	lda #9 ; cloud is 16 pixel height 
	sta ch1
	lda #24 ; bullet is 24 pixel wide
	sta cw1


	ldy #0				; Load Y with 0
	lda #0				; Load X with 0
@loop:
	lda enemydata,y		; Get ennemy Y in list
	beq @skip			; Branch on Equal - Branch if zero flag is set - if ennemy is not used branch to skip

	; enemy is on screen
	; calculate first sprite oam position
	tya					; Transfert Y to A
	; Compute OAM index (index x 16)
	asl 				; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	clc					; Clear Carry flag
	adc #24 			; Add with Carry (+24) - shift OAM position already used by player cloud
	tax					; Transfert A to X

	; Get current Y position
	lda oam,x 			; Load A with enemy Y
	clc					; Clear Carry flag
	adc #1 				; Add with carry (+1)
	cmp bottom_line			; Compare with bottom virtual line position
	bcc @nohitbottom	; Branch on Carry Clear - Till position is lower than virtual bottom line, the carry flag is not set
	; has reached the ground
	lda #255			; Load A with 255 (this specific psoition indicate that sprite is not in use)
	sta oam,x 			; Store new Y position to sprite (hide all sprites)
	sta oam+4,x			; sprite 2
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; clear the enemies in use flag
	lda #0 				; Load A with 0
	sta enemydata,y		; Set use flag
	jmp @skip			; skip next part

	@nohitbottom:
	; save the new Y position
	sta oam,x 			; Sprite 1
	sta oam+4,x			; sprite 2
	clc					; Clear Carry flag
	adc #8				; Add 8
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; Detection with player
	lda oam,x ; get enemy y position
	clc
	adc #1
	sta cy2
	lda oam+3,x ; get enemy x position
	clc
	adc #3
	sta cx2
	lda #10 ; set enemy width
	sta cw2
	lda #17 ; set enemy height
	sta ch2
	jsr collision_test
	bcc @skip

	; Player hit ennemy
	lda #$ff
	sta oam,x ; erase enemy
	sta oam+4,x
	sta oam+8,x
	sta oam+12,x
	lda #0 ; clear enemy's data flag
	sta enemydata,y

@skip:
	iny 				; Increment Y goto to next enemy
	cpy #10				; Compare Y with 10
	bne @loop			; Branch Not Equal - Branch if zero flag is not set. Till Y < 10, loop

	rts					; exit
.endproc

;*****************************************************************
; Spawn Heart
;*****************************************************************
.segment "CODE"

.proc spawn_heart
	; Check if an heart can pop
	ldx heartcooldown 		; Load X with heart cooldown value
	dex						; Decrement X
	stx heartcooldown		; Store heart cooldown wit new value
	cpx #0					; Compare with 0
	beq :+					; Branch on equal - If zero flag is set branch - CPX return a zero flag when X equal 0 -> skip rts instruction
		rts					; Exit subroutine - not yet
	:

	; Spawn an heart based on psuedo RNG
	ldx #1 					; Load X with 1
	stx heartcooldown		; Store it into heart cooldown -> to rpevent an error for the next call of this subroutine (next call will decrease cooldown by 1)

	lda #1	 				; Load A with current level
	clc						; Clear Carry flag
	adc #1 					; Add with Carry - increment by 1 the level
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	; +--> Result A is multiply by 4
	sta temp 				; Store A into temp adress - save our value
	jsr rand 				; Call rand routine - get next random value
	tay 					; transfer A into Y
	cpy temp				; Compare Y with temp (i.e. (lvl +1 ) * 4)
	; continue if random value less than our calculated value
	bcc :+ 					; Branch if Carry Clear - CPY set carry flag is Y >= M. If random value is less than our difficulty value an heart pop, other xise exit
		rts					; exit
	:

	; An heart pop - Reset cooldown value to intial value
	ldx #20 				; Load A with 20 - set new cool down period
	stx heartcooldown		; Store A into cooldown adress
	
	; Check if an ennemy can be displayed (max 3 heart on screen)
	ldy #0 					; Load Y with 0 - counter of heart list

@loop:
	lda heardata,y			; Load A with ennemy Y
	beq :+					; Branch on equal - If zero flag is set branch - Zero flag means ennmy is available (zero value). :+ means branch to next unlabeled tag
	iny 					; increment counter
	cpy #2					; Compare to 3 - max ennemy list
	bne @loop				; Branch if Not Equal - If zero flag flag is clear branch -> Y equal 3
		; did not find an heart to use
		rts					; After the loop if no enenmy is available, exit
	:

	; mark the heart as in use
	lda #1					; Load A with 1
	sta heardata,y			; Store into ennemy byte

	; calculate first sprite oam position
	; Each heart use 4 sprites (4 bytes eache). We must defines the first index of sprites in OAM based on heart index:
	; Ennemy 0: 0
	; Ennemy 1: 16
	; ennemy 2: 32
	; ...
	; position on ennemy n: n * 16
	tya						; Transfert Y to A - Get current ennemy index
	; multiply by 16
	asl 					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x4) 
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x8)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x16)

	; The first 6 sprites are used by the player cloud. Each sprites takes 4 bytes. The position is then shifted by 24 ((6+40) x 4)
	; Ennemy 0 -> position 24 in OAM; Ennemy 1 -> position 36 ...
	clc						; Clear Carry flag
	adc #184 				; Add with Carry - shift OAM position by 24
	tax						; Transfert A to X

	; now setup the heart sprite
	; set the Y position (byte 0) of all four parts of the player ship
	lda #0					; Load A with 0 (top position Y)
	sta oam,x				; Sprite 1
	sta oam+4,x				; Sprite 2
	lda #8					; Load A with 8 (bottom line of sprites)
	sta oam+8,x				; sprite 3
	sta oam+12,x			; sprite 4
	
	; set the index number (byte 1) of the sprite pattern
	lda #10 					; Set Sprite index (10 in CHR)
	sta oam+1,x				; Sprite 1	
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+5,x				; Sprite 2
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+9,x				; Sprite 3
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+13,x			; Sprite 4
	
	; set the sprite attributes (byte 2)
	lda #%00000010			; Load A with 00000010 mask
	sta oam+2,x				; Sprite 1
	sta oam+6,x				; Sprite 2
	sta oam+10,x			; Sprite 3
	sta oam+14,x			; Sprite 4

	; set the X position (byte 3)  of all four parts of the player ship
	jsr rand				; Call Random routine
	and #%11110000			; AND to get only higher bits
	clc						; Carry clear
	adc #48					; Add with carry (+48)
	sta oam+3,x				; Sprite 1
	sta oam+11,x			; Sprite 3
	clc						; Carry clear
	adc #8					; Add with carry (+8)
	sta oam+7,x				; Sprite 2
	sta oam+15,x			; Sprite 4

	rts						; Exit
.endproc

;*****************************************************************
; Move heart downward
;*****************************************************************
.segment "CODE"

.proc move_heart

	; setup for collision detection with player
	lda oam ; get cloud Y position
	clc
	adc #5
	sta cy1
	lda oam+3 ; get cloud x position
	sta cx1
	lda #9 ; cloud is 16 pixel height 
	sta ch1
	lda #24 ; bullet is 24 pixel wide
	sta cw1

	ldy #0				; Load Y with 0
	lda #0				; Load X with 0
@loop:
	lda heardata,y		; Get ennemy Y in list
	beq @skip			; Branch on Equal - Branch if zero flag is set - if ennemy is not used branch to skip

	; enemy is on screen
	; calculate first sprite oam position
	tya					; Transfert Y to A
	; Compute OAM index (index x 16)
	asl 				; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	clc					; Clear Carry flag
	adc #184 			; Add with Carry (+24) - shift OAM position already used by player cloud
	tax					; Transfert A to X

	; Get current Y position
	lda oam,x 			; Load A with enemy Y
	clc					; Clear Carry flag
	adc #1 				; Add with carry (+1)
	cmp bottom_line			; Compare with bottom virtual line position
	bcc @nohitbottom	; Branch on Carry Clear - Till position is lower than virtual bottom line, the carry flag is not set
	; has reached the ground
	lda #255			; Load A with 255 (this specific psoition indicate that sprite is not in use)
	sta oam,x 			; Store new Y position to sprite (hide all sprites)
	sta oam+4,x			; sprite 2
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; clear the enemies in use flag
	lda #0 				; Load A with 0
	sta heardata,y		; Set use flag
	jmp @skip			; skip next part

	@nohitbottom:
	; save the new Y position
	sta oam,x 			; Sprite 1
	sta oam+4,x			; sprite 2
	clc					; Clear Carry flag
	adc #8				; Add 8
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; Detection with player
	lda oam,x ; get enemy y position
	clc
	adc #1 ; first row is empty
	sta cy2
	lda oam+3,x ; get enemy x position
	clc
	adc #2
	sta cx2
	lda #11 ; set enemy width 
	sta cw2
	lda #10 ; set enemy height
	sta ch2
	jsr collision_test
	bcc @skip

	; Player hit ennemy
	lda #$ff
	sta oam,x ; erase enemy
	sta oam+4,x
	sta oam+8,x
	sta oam+12,x
	lda #0 ; clear enemy's data flag
	sta heardata,y

@skip:
	iny 				; Increment Y goto to next enemy
	cpy #2			; Compare Y with 10
	bne @loop			; Branch Not Equal - Branch if zero flag is not set. Till Y < 10, loop

	rts					; exit
.endproc

;*****************************************************************
; Spawn Bolt
;*****************************************************************
.segment "CODE"

.proc spawn_bolt
	; Check if an heart can pop
	ldx boltcooldown 		; Load X with heart cooldown value
	dex						; Decrement X
	stx boltcooldown		; Store heart cooldown wit new value
	cpx #0					; Compare with 0
	beq :+					; Branch on equal - If zero flag is set branch - CPX return a zero flag when X equal 0 -> skip rts instruction
		rts					; Exit subroutine - not yet
	:

	; Spawn an heart based on psuedo RNG
	ldx #1 					; Load X with 1
	stx boltcooldown		; Store it into heart cooldown -> to rpevent an error for the next call of this subroutine (next call will decrease cooldown by 1)

	lda #1	 				; Load A with current level
	clc						; Clear Carry flag
	adc #1 					; Add with Carry - increment by 1 the level
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear
	; +--> Result A is multiply by 4
	sta temp 				; Store A into temp adress - save our value
	jsr rand 				; Call rand routine - get next random value
	tay 					; transfer A into Y
	cpy temp				; Compare Y with temp (i.e. (lvl +1 ) * 4)
	; continue if random value less than our calculated value
	bcc :+ 					; Branch if Carry Clear - CPY set carry flag is Y >= M. If random value is less than our difficulty value an heart pop, other xise exit
		rts					; exit
	:

	; An heart pop - Reset cooldown value to intial value
	ldx #20 				; Load A with 20 - set new cool down period
	stx boltcooldown		; Store A into cooldown adress
	
	; Check if an ennemy can be displayed (max 3 heart on screen)
	ldy #0 					; Load Y with 0 - counter of heart list

@loop:
	lda boltdata,y			; Load A with ennemy Y
	beq :+					; Branch on equal - If zero flag is set branch - Zero flag means ennmy is available (zero value). :+ means branch to next unlabeled tag
	iny 					; increment counter
	cpy #1					; Compare to 1 - max bolt list
	bne @loop				; Branch if Not Equal - If zero flag flag is clear branch -> Y equal 3
		; did not find an heart to use
		rts					; After the loop if no enenmy is available, exit
	:

	; mark the heart as in use
	lda #1					; Load A with 1
	sta boltdata,y			; Store into ennemy byte

	; calculate first sprite oam position
	; Each heart use 4 sprites (4 bytes eache). We must defines the first index of sprites in OAM based on heart index:
	; Ennemy 0: 0
	; Ennemy 1: 16
	; ennemy 2: 32
	; ...
	; position on ennemy n: n * 16
	tya						; Transfert Y to A - Get current ennemy index
	; multiply by 16
	asl 					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x4) 
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x8)
	asl						; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2) (-> x16)

	; The first 6 sprites are used by the player cloud. Each sprites takes 4 bytes. The position is then shifted by 24 ((6+40+3) x 4)
	; Ennemy 0 -> position 24 in OAM; Ennemy 1 -> position 36 ...
	clc						; Clear Carry flag
	adc #216 				; Add with Carry - shift OAM position by 24
	tax						; Transfert A to X

	; now setup the heart sprite
	; set the Y position (byte 0) of all four parts of the player ship
	lda #0					; Load A with 0 (top position Y)
	sta oam,x				; Sprite 1
	sta oam+4,x				; Sprite 2
	lda #8					; Load A with 8 (bottom line of sprites)
	sta oam+8,x				; sprite 3
	sta oam+12,x			; sprite 4
	
	; set the index number (byte 1) of the sprite pattern
	lda #14					; Set Sprite index (14 in CHR)
	sta oam+1,x				; Sprite 1	
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+5,x				; Sprite 2
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+9,x				; Sprite 3
	clc						; Carry clear
	adc #1					; Add with Carry (+1)
	sta oam+13,x			; Sprite 4
	
	; set the sprite attributes (byte 2)
	lda #%00000010			; Load A with 00000010 mask
	sta oam+2,x				; Sprite 1
	sta oam+6,x				; Sprite 2
	sta oam+10,x			; Sprite 3
	sta oam+14,x			; Sprite 4

	; set the X position (byte 3)  of all four parts of the player ship
	jsr rand				; Call Random routine
	and #%11110000			; AND to get only higher bits
	clc						; Carry clear
	adc #48					; Add with carry (+48)
	sta oam+3,x				; Sprite 1
	sta oam+11,x			; Sprite 3
	clc						; Carry clear
	adc #8					; Add with carry (+8)
	sta oam+7,x				; Sprite 2
	sta oam+15,x			; Sprite 4

	rts						; Exit
.endproc

;*****************************************************************
; Move heart downward
;*****************************************************************
.segment "CODE"

.proc move_bolt
	; setup for collision detection with player
	lda oam ; get cloud Y position
	clc
	adc #5
	sta cy1
	lda oam+3 ; get cloud x position
	sta cx1
	lda #9 ; cloud is 16 pixel height 
	sta ch1
	lda #24 ; bullet is 24 pixel wide
	sta cw1

	ldy #0				; Load Y with 0
	lda #0				; Load X with 0
@loop:
	lda boltdata,y		; Get ennemy Y in list
	beq @skip			; Branch on Equal - Branch if zero flag is set - if ennemy is not used branch to skip

	; enemy is on screen
	; calculate first sprite oam position
	tya					; Transfert Y to A
	; Compute OAM index (index x 16)
	asl 				; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	asl					; Arithmetic Shift Left : A = A << 1 - bit 7 of old A is set to C and new byte 0 of A is clear (x2)
	clc					; Clear Carry flag
	adc #216			; Add with Carry (+24) - shift OAM position already used by player cloud
	tax					; Transfert A to X

	; Get current Y position
	lda oam,x 			; Load A with enemy Y
	clc					; Clear Carry flag
	adc #1 				; Add with carry (+1)
	cmp bottom_line			; Compare with bottom virtual line position
	bcc @nohitbottom	; Branch on Carry Clear - Till position is lower than virtual bottom line, the carry flag is not set
	; has reached the ground
	lda #255			; Load A with 255 (this specific psoition indicate that sprite is not in use)
	sta oam,x 			; Store new Y position to sprite (hide all sprites)
	sta oam+4,x			; sprite 2
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; clear the enemies in use flag
	lda #0 				; Load A with 0
	sta boltdata,y		; Set use flag
	jmp @skip			; skip next part

	@nohitbottom:
	; save the new Y position
	sta oam,x 			; Sprite 1
	sta oam+4,x			; sprite 2
	clc					; Clear Carry flag
	adc #8				; Add 8
	sta oam+8,x			; sprite 3
	sta oam+12,x		; sprite 4

	; Detection with player
	lda oam,x ; get enemy y position
	sta cy2
	lda oam+3,x ; get enemy x position
	clc
	adc #3		; Add with carry - Bolt sprite has 3 first column empty.
	sta cx2
	lda #10 ; set enemy width
	sta cw2
	lda #15 ; set enemy width
	sta ch2
	jsr collision_test
	bcc @skip

	; Player hit ennemy
	lda #$ff
	sta oam,x ; erase enemy
	sta oam+4,x
	sta oam+8,x
	sta oam+12,x
	lda #0 ; clear enemy's data flag
	sta boltdata,y

@skip:
	iny 				; Increment Y goto to next enemy
	cpy #1				; Compare Y with 10
	bne @loop			; Branch Not Equal - Branch if zero flag is not set. Till Y < 10, loop

	rts					; exit
.endproc


;*****************************************************************
; Display Title Screen
;*****************************************************************
.segment "ZEROPAGE"
paddr: .res 2 ; 16-bit address pointer

.segment "CODE"
title_text:
.byte "R A I N  F A L L",0

press_play_text:
.byte "PRESS FIRE TO BEGIN",0

title_attributes:
.byte %00000101,%00000101,%00000101,%00000101
.byte %00000101,%00000101,%00000101,%00000101

.proc display_title_screen
	jsr ppu_off 												; Wait for the screen to be drawn and then turn off drawing
	jsr clear_nametable 										; Clear the 1st name table

	; Write the title text
	vram_set_address (NAME_TABLE_0_ADDRESS + 4 * 32 + 7)		; Set VRAM position (tiles index set at table 0 start index + line shift + row shift) -> Here 4 lines and 7 colones from top left position
	assign_16i text_address, title_text							; Assign 16 bit adress
	jsr write_text												; Write text at specified position

	; Write our press play text
	vram_set_address (NAME_TABLE_0_ADDRESS + 20 * 32 + 6)		; Set VRAM position
	assign_16i text_address, press_play_text					; Assign 16 bit adress
	jsr write_text												; Write text at specified position

	; Set the title text to use the 2nd palette entries - 8 adress
	vram_set_address (ATTRIBUTE_TABLE_0_ADDRESS + 8)			; Get position of the palette
	assign_16i paddr, title_attributes							; Assign 16 bit adress

	ldy #0														; Load Y with 0
loop:
	lda (paddr),y												; Load address + Y (palette)
	sta PPU_VRAM_IO												; Store palette
	iny															; Increment Y
	cpy #8														; Compare with 8
	bne loop													; Branch not equal - Zero flag not set - Till Y is not equal to 8 branch is active


	jsr ppu_update ; Wait until the screen has been drawn

	rts
.endproc


;*****************************************************************
; Display Main Game Screen
;*****************************************************************
.segment "RODATA"
game_cloud_1:
	.byte $07,$04,$05,$06,$07,$02,$02,$02,$04,$05,$03,$06,$07,$02,$04,$07
	.byte $02,$02,$04,$05,$06,$09,$06,$07,$02,$04,$07,$02,$02,$02,$04,$05
game_cloud_2:
	.byte $0D,$0E,$0A,$0B,$0C,$0D,$0A,$0F,$0C,$0D,$08,$0A,$0B,$0C,$0D,$0A
	.byte $0F,$0C,$0D,$0A,$0D,$0E,$0A,$0B,$02,$0C,$0F,$0B,$0C,$0D,$0E,$0A
game_cloud_3:
	.byte $12,$13,$14,$10,$11,$12,$13,$10,$15,$12,$15,$12,$13,$14,$10,$11
	.byte $12,$13,$10,$13,$10,$11,$12,$13,$16,$10,$13,$10,$15,$12,$13,$14

game_screen_scoreline:
	.byte $00,"S","C","O","R","E",$21,"0","0","0","0","0","0",$00,$00,$00
	.byte $17,$17,$17,$17,$17,$00,$00,$00,$00,$00,$00,"0",$22,$18,$00,$00

;**
; Each byte define a meta-tile composed of 4tiles :
; +--+--+
; |10|32|
; +--+--+
; |54|76|
; +--+--+
; Each byte compose the next meta-tiles.
;**
bg_attributes:
	.byte %01010101,%01010101,%01010101,%01010101
	.byte %01010101,%01010101,%01010101,%01010101

.segment "CODE"
.proc display_game_screen
	jsr ppu_off ; Wait for the screen to be drawn and then turn off drawing

	jsr clear_nametable ; Clear the 1st name table

	; Draw first line with cloud color
	vram_set_address (NAME_TABLE_0_ADDRESS) 	; first line draw
	assign_16i paddr, game_cloud_1
	ldy #$00
loop1:
	lda (paddr),y
	sta PPU_VRAM_IO
	iny
	cpy #32
	bne loop1

	; Draw second line with cloud color
	vram_set_address (NAME_TABLE_0_ADDRESS + 1 * 32) 	; second line draw
	assign_16i paddr, game_cloud_2
	ldy #$00
loop2:
	lda (paddr),y
	sta PPU_VRAM_IO
	iny
	cpy #32
	bne loop2

	; Draw line 3 with cloud color
	vram_set_address (NAME_TABLE_0_ADDRESS + 2 * 32) 	; line 3 draw
	assign_16i paddr, game_cloud_3
	ldy #$00
loop3:
	lda (paddr),y
	sta PPU_VRAM_IO
	iny
	cpy #32
	bne loop3

	; output the score section
	vram_set_address (NAME_TABLE_0_ADDRESS + 28 * 32) 	; line 26 draw
	assign_16i paddr, game_screen_scoreline
	ldy #$00
loop4:
	lda (paddr),y
	sta PPU_VRAM_IO
	iny
	cpy #32
	bne loop4

	; Set the title text to use the 2nd palette entries - 8 adress
	vram_set_address ATTRIBUTE_TABLE_0_ADDRESS				; Get position of the palette
	assign_16i paddr, bg_attributes								; Assign 16 bit adress

	ldy #0														; Load Y with 0
loopC:
	lda (paddr),y												; Load address + Y (palette)
	sta PPU_VRAM_IO												; Store palette
	iny															; Increment Y
	cpy #8														; Compare with 8
	bne loopC													; Branch not equal - Zero flag not set - Till Y is not equal to 8 branch is active




	jsr ppu_update ; Wait until the screen has been drawn
	rts

.endproc

;*****************************************************************
; Our default palette table 16 entries for tiles and 16 entries for sprites
;*****************************************************************

;; Read Only DATA
.segment "RODATA"
default_palette:
.byte $0F,$15,$26,$37 ; bg0 purple/pink
.byte $0F,$0C,$1C,$2C ; bg1 Blue
.byte $0F,$01,$11,$21 ; bg2 blue
.byte $0F,$00,$10,$30 ; bg3 greyscale
.byte $0F,$2C,$3C,$30 ; sp0 blue / white
.byte $0F,$11,$21,$31 ; sp1 Blue
.byte $0F,$15,$26,$37 ; sp2 purple/pink
.byte $0F,$12,$22,$32 ; sp3 marine
