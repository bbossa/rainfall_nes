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

	; draw the game screen
	jsr display_game_screen

	; display the player's cloud
	; set the Y position (byte 0) of all six parts of the player cloud
	lda #196
	sta oam
	sta oam+4
	sta oam+8
	lda #204	; 196 + 8
	sta oam+12
	sta oam+16
	sta oam+20
	; Set index number (byte 1) of the sprite pattern
	ldx #0
	stx oam+1
	inx
	stx oam+5
	inx
	stx oam+9
	inx
	stx oam+13
	inx
	stx oam+17
	inx
	stx oam+21
	; set the sprite attributes (byte 2)
	lda #%00000000
	sta oam+2
	sta oam+6
	sta oam+10
	sta oam+14
	sta oam+18
	sta oam+22

	; set the X position (byte 3)  of all six parts of the player cloud
	lda #112
	sta oam+3
	sta oam+15
	lda #120 ; 120
	sta oam+7
	sta oam+19
	lda #128 ; 120 + 8
	sta oam+11
	sta oam+23

	jsr ppu_update


mainloop:
	lda time

	; ensure the time has actually changed
	cmp lasttime
	beq mainloop

	; time has changed update the lasttime value
	sta lasttime

	jsr player_actions

	; ensure our changes are rendered
 	lda #1
 	sta nmi_ready

	jmp mainloop

 .endproc

 ;*****************************************************************
; Check for the game controller, move the player
;*****************************************************************
.segment "CODE"
.proc player_actions
	jsr gamepad_poll
	lda gamepad
	and #PAD_L
	beq not_gamepad_left
		; game pad has been pressed left
		lda oam + 3 ; get current x of cloud
		cmp #0
		beq not_gamepad_left
		; subtract 1 from the ship position
		sec
		sbc #2
		; update the four sprites that make up the ship
		sta oam + 3
		sta oam + 15
		clc
		adc #8
		sta oam + 7
		sta oam + 19
		clc
		adc #8
		sta oam + 11
		sta oam + 23
		
not_gamepad_left:
	lda gamepad
	and #PAD_R
	beq not_gamepad_right
		; gamepad has been pressed right
		; gamepad has been pressed right
		lda oam + 3 ; get current X of cloud
		clc
		adc #22 ; allow with width of cloud
		cmp #254
		beq not_gamepad_right
		lda oam + 3 ; get current X of cloud
		clc
		adc #2
		; update the four sprites that make up the ship
		sta oam + 3
		sta oam + 15
		clc
		adc #8
		sta oam + 7
		sta oam + 19
		clc
		adc #8
		sta oam + 11
		sta oam + 23
not_gamepad_right:
	rts
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
.byte $0F,$14,$24,$34 ; sp1 purple
.byte $0F,$1B,$2B,$3B ; sp2 teal
.byte $0F,$12,$22,$32 ; sp3 marine
