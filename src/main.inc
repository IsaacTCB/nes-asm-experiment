.ifndef _MAIN_INC
.define _MAIN_INC

; ------------------
;     Macros
; ------------------

; Gamepad

.macro checkbtn btn
    lda buttons
    and btn
.endmacro

.macro checkbtn_pressed btn
    lda lastbuttons
    eor #$FF
    and buttons
    and btn
.endmacro

.macro checkbtn_released btn
    lda buttons
    eor #$FF
    and lastbuttons
    and btn
.endmacro

; ------------------
;     Zeropage
; ------------------

.globalzp temp
.globalzp buttons
.globalzp lastbuttons
.globalzp player_x
.globalzp player_y
.globalzp player_vel_x
.globalzp player_vel_y
.globalzp player_input_dir
.globalzp draw_pos

; ------------------
;     Tilemap
; ------------------

.global tilemap

; ------------------
;       Misc.
; ------------------

.global div16_table

.endif ; _MAIN_INC
