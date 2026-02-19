;******************************************************************************
; Macro can be seen as function defined into a specific part of the binary
; Allow to pass parameters
; Allow to reduce code line in the main PRG
;******************************************************************************

;******************************************************************************
; Assigning a 16-bit address
; This macro has two parameters. The first is the location in zero-page
; memory where we want to write the 16-bit address, and the second is
; the 16-bit address.
;******************************************************************************
.macro assign_16i dest, value
    lda #<value     ; Split 16 bit and keep lower value
    sta dest+0      ; Store to adress dest
    lda #>value     ; Split 16 bit and keep higher value
    sta dest+1      ; Store to adress dest + 1

.endmacro

;******************************************************************************
; Set the vram address pointer to the specified address
; This macro set a new adress to the VRAM
;******************************************************************************
.macro vram_set_address newaddress

   lda PPU_STATUS           ; reset address latch
   lda #>newaddress         ; Get higher value of adress
   sta PPU_VRAM_ADDRESS2    ; Set to VRAM
   lda #<newaddress         ; Get lower value of adress
   sta PPU_VRAM_ADDRESS2    ; Set to VRAM

.endmacro

;******************************************************************************
; clear the vram address pointer
;******************************************************************************
.macro vram_clear_address

   lda #0
   sta PPU_VRAM_ADDRESS2
   sta PPU_VRAM_ADDRESS2

.endmacro