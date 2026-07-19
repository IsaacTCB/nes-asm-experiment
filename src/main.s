.include "main.inc"
.include "common.inc"

PLAYER_ACC = $0040
PLAYER_FRC = $0020
PLAYER_GRV = $0020

PLAYER_MAX_VSP = $0700
PLAYER_MAX_VSP_NEGATIVE = (-PLAYER_MAX_VSP)

PLAYER_WIDTH = 6
PLAYER_HEIGHT = 6

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

.segment "HEADER"
    .byte "NES" ; id string
    .byte $1A
    .byte $02   ; amount of PRG ROM in 16K units
    .byte $01   ; amount of CHR ROM in 8k units
    .byte $00   ; mapper and mirroing
    .byte $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00

.segment "ZEROPAGE"
    nmi_lock: .res $01
    nmi_frame: .res $01
    ppu_ready: .res $01
    draw_pos: .res $02
    buttons: .res $01
    lastbuttons: .res $01
    player_x: .res $02
    player_y: .res $02
    player_input_dir: .res $01
    player_vel_x: .res $02
    player_vel_y: .res $02
    scroll_x: .res $01
    scroll_y: .res $01
    temp: .res $08

.segment "BSS"
    ppu_palette: .res $20

.segment "STARTUP"

.export reset_handler

.proc reset_handler
    sei ; disables interrupts
    cld ; turn off decimal mode

    ; disable APU frame IRQ
    ldx #%010000000
    stx $4017

    ; initialize stack pointer to $01ff
    ldx #$FF
    txs
    lda #$00
    sta $2000 ; disable NMI
    sta $2001 ; disable Rendering
    sta $4010 ; disable PCM

    ; ensures that wait for vblank actually works
    bit $2002
    wait_for_vblank

    ldx #0
@clearmem:
    lda #$00
    sta $0000, X
    sta $0100, X
    sta $0300, X
    sta $0400, X
    sta $0500, X
    sta $0600, X
    sta $0700, X
    lda #$FE
    sta $0200, X
    inx
    bne @clearmem

    wait_for_vblank

    jsr load_palette

    sta $2002
    lda #$20
    sta $2006
    lda #$00
    sta $2006
    jsr load_background

    sta $2002
    lda #$28
    sta $2006
    lda #$00
    sta $2006
    jsr load_background

    ; enable interrupts and start nmi
    cli
    lda #%10010000
    sta $2000

    lda #$40
    sta player_x
    lda #$30
    sta player_y

@loop:
    jsr ppu_wait

    lda buttons
    sta lastbuttons
    jsr poll_gamepad_safe

    lda #$00
    sta player_input_dir

    ; move left
    checkbtn #PAD_L
    beq :+
        lda #$FF
        sta player_input_dir
    :

    ; move right
    checkbtn #PAD_R
    beq :+
        ; fix for some controllers/emulators
        ; where you can press left and right
        ; simultaneously.
        lda player_input_dir
        beq @not_moving_left
        lda #$00
        sta player_input_dir
        jmp :+

    @not_moving_left:
        lda #$01
        sta player_input_dir
    :

    ; jumping 
    checkbtn_pressed #PAD_B
    beq :+
        lda #$FC
        sta player_vel_y+0
        lda #$00
        sta player_vel_y+1
    :

    ; fly 
    checkbtn #PAD_A
    beq :+
        lda #$FD
        sta player_vel_y+0
        lda #$00
        sta player_vel_y+1
    :

    lda player_input_dir
    beq @player_friction
    bmi @player_move_left
    bpl @player_move_right

@player_friction:
    jsr player_apply_friction
    jmp @player_done

@player_move_left:
    jsr player_move_left
    jmp @player_done

@player_move_right:
    jsr player_move_right
    ; jmp @player_done

@player_done:
    jsr player_apply_movement

    lda player_x
    sta draw_pos+0
    lda player_y
    sta draw_pos+1
    lda #1
    jsr draw_player_sprite

    jmp @loop

.endproc

.export irq_handler
.proc irq_handler
    rti
.endproc

.segment "CODE"

.export nmi_handler
.proc nmi_handler
    ; store registers in stack
    pha
    txa
    pha
    tya
    pha

    lda nmi_lock
    bne @nmi_end

    ; lock NMI
    lda #$01
    sta nmi_lock

    inc nmi_frame
    jsr update_ppu

    ; unlock NMI, we are done
    lda #$00
    sta nmi_lock

@nmi_end:
    pla
    tay
    pla
    tax
    pla

    rti
.endproc

.proc update_ppu
    ; ppu_ready == 0 not ready to update
    lda ppu_ready
    beq @ppu_update_end
    ; ppu_ready == 2 disables rendering
    cmp #2
    bne @ppu_update_start

@ppu_disable:
    lda #%00000000
    sta $2001
    sta ppu_ready
    jmp @ppu_update_end

@ppu_update_start:
    ; copy OAM using DMA
    ldx #0
    stx $2003
    lda #>OAM
    sta $4014

    ; copy palette
    lda $2002
    lda #$3F
    sta $2006
    stx $2006
@ppu_copy_palette:
    lda ppu_palette, X
    sta $2007
    inx
    cpx #$20
    bcc @ppu_copy_palette

    lda #%10010000
    sta $2000

    ; reset scroll
    lda $2002
    lda scroll_x
    sta $2005
    lda scroll_y
    sta $2005

    ; enable rendering
	lda #%00011110
	sta $2001

    lda #%00
    sta ppu_ready

@ppu_update_end:
    rts
.endproc

.export ppu_wait
.proc ppu_wait
    lda #1
    sta ppu_ready

@wait_for_ppu:
    lda ppu_ready
    bne @wait_for_ppu

    rts
.endproc

.export ppu_stop
.proc ppu_stop
    lda #2
    sta ppu_ready

@wait_for_ppu:
    lda ppu_ready
    bne @wait_for_ppu

    rts
.endproc

.proc load_palette
    ldx #0
@loop:
    lda PALETTE,x
    sta ppu_palette,x
    inx
    cpx #$20
    bne @loop

    rts
.endproc

; A -> oam sprite index
; draw_pos[0] -> x coords
; draw_pos[1] -> y coords
.proc draw_player_sprite
    asl a
    asl a
    tax
    ; y coord
    lda draw_pos+1
    sec
    sbc #9
    sta OAM+0, x
    sta OAM+4, x
    clc
    adc #8
    sta OAM+8, x
    sta OAM+12, x
    inx

    ; sprite
    lda #$00
    sta OAM+0, x
    lda #$01
    sta OAM+4, x
    lda #$10
    sta OAM+8, x
    lda #$11
    sta OAM+12, x
    inx

    ; attr
    lda #0
    sta OAM+0, x
    sta OAM+4, x
    sta OAM+8, x
    sta OAM+12, x
    inx

    ; x coord
    lda draw_pos+0
    sec
    sbc #7
    sta OAM+0, x
    sta OAM+8, x
    clc
    adc #8
    sta OAM+4, x
    sta OAM+12, x

    rts
.endproc

; result is stored in accumulator,
; does not write `buttons`.
.proc poll_gamepad
    ; strobe the gamepad to latch current button state
    ; whenever latch is open, the controller enters
    ; parallel mode, meaning it updates each button
    ; in its internal "memory"
	lda #1
	sta GAMEPAD1
    ; writing #0 to gamepad closes the latch.
    ; once the latch is closed, the controller
    ; freezes its internal "memory" and enters
    ; serial mode so that we can read each button
    ; state.
	lda #0
	sta GAMEPAD1
	; read 8 bytes from the interface at $4016
    ;
    ; the controller only sends 1 bit per read.
    ; each bit represents a button.
	ldx #8
	:
        ; push buttons bitset into stack
		pha
		; first low bit is the button value
        ; second low bit is the expansion port button value (famicom)
		lda GAMEPAD1
		and #%00000011
        ; cmp checks if either one of the two bits are
        ; set, then stores the result into carry bit.
		cmp #%00000001
        ; restore buttons bitset from stack
		pla
		; rotate carry into button bitset
		ror
		dex
		bne :-
	rts
.endproc

; the good old SMB3 safe gamepad polling function
; to fix corrupted reads due to DPCM.
;
; result is stored in `buttons`
.proc poll_gamepad_safe
    jsr poll_gamepad

@loop:
    sta buttons
    jsr poll_gamepad
    cmp buttons
    bne @loop

    rts
.endproc

.proc load_background
    ; set PPU address to $2000
    lda #$20
    sta $2006
    lda #$00
    sta $2006

    ldx #0 ; index into tilemap
    ldy #15 ; number of source rows

@row:
    ; first copy of the row
    lda #16
    sta temp

@copy1:
    lda tilemap, x
    cmp #1
    beq @solid1
    lda #0
    jmp @write1

@solid1:
    lda #$FF

@write1:
    sta $2007
    sta $2007 ; scales tileset horizontally

    inx
    dec temp
    bne @copy1

    ; rewind X so we can reread the same row
    txa
    sec
    sbc #16
    tax

    ; second copy of the row
    lda #16
    sta temp

@copy2:
    lda tilemap, x
    cmp #1
    beq @solid2
    lda #0
    jmp @write2

@solid2:
    lda #$FF

@write2:
    sta $2007
    sta $2007

    inx
    dec temp
    bne @copy2

    dey
    bne @row

    rts
.endproc

; ====================
;       Player
; ====================

.proc player_move_left
    lda player_vel_x+1
    sec
    sbc #<PLAYER_ACC
    sta player_vel_x+1
    lda player_vel_x+0
    sbc #>PLAYER_ACC
    sta player_vel_x+0
    rts
.endproc

.proc player_move_right
    lda player_vel_x+1
    clc
    adc #<PLAYER_ACC
    sta player_vel_x+1
    lda player_vel_x+0
    adc #>PLAYER_ACC
    sta player_vel_x+0
    rts
.endproc

.proc player_gravity
    lda player_vel_y+1
    clc
    adc #<PLAYER_GRV
    sta player_vel_y+1
    lda player_vel_y+0
    adc #>PLAYER_GRV
    sta player_vel_y+0

@check_sign:
    lda player_vel_y
    bpl @moving_downwards

    ; if (player_vel_y[0] <= #<PLAYER_MAX_VSP_NEGATIVE
    ;  && player_vel_y[1] < #>PLAYER_MAX_VSP_NEGATIVE) {
    ;     player_vel_y[0] = #<PLAYER_MAX_VSP_NEGATIVE;
    ;     player_vel_y[1] = #>PLAYER_MAX_VSP_NEGATIVE;
    ; }
@moving_upwards:
    lda player_vel_y + 0
    cmp #>PLAYER_MAX_VSP_NEGATIVE
    bmi :+
    bne @done
:
    lda player_vel_y + 1
    cmp #<PLAYER_MAX_VSP_NEGATIVE
    bmi @clamp_up_velocity
    jmp @done

@clamp_up_velocity:
    lda #>PLAYER_MAX_VSP_NEGATIVE
    sta player_vel_y+0
    lda #<PLAYER_MAX_VSP_NEGATIVE
    sta player_vel_y+1
    rts

    ; if (player_vel_y[0] >= #<PLAYER_MAX_VSP
    ;  && player_vel_y[1] > #>PLAYER_MAX_VSP) {
    ;     player_vel_y[0] = #<PLAYER_MAX_VSP;
    ;     player_vel_y[1] = #>PLAYER_MAX_VSP;
    ; }
@moving_downwards:
    lda player_vel_y + 0
    cmp #>PLAYER_MAX_VSP
    bmi @done
    lda player_vel_y + 1
    cmp #<PLAYER_MAX_VSP
    beq @done
    bmi @done

@clamp_down_velocity:
    lda #>PLAYER_MAX_VSP
    sta player_vel_y+0
    lda #<PLAYER_MAX_VSP
    sta player_vel_y+1
    rts

@done:
    rts
.endproc

.macro ADD16 position, velocity
    lda position+1
    clc
    adc velocity+1
    sta position+1
    lda position+0
    adc velocity+0
    sta position+0
.endmacro

.proc player_apply_friction
    ; if velocity is exactly 0, do nothing.
    lda player_vel_x
    bne @check_sign
    lda player_vel_x+1
    beq @done

@check_sign:
    bmi @left_friction

@right_friction:
    sec
    lda player_vel_x+1
    sbc #<PLAYER_FRC
    sta player_vel_x+1
    lda player_vel_x
    sbc #>PLAYER_FRC

    ; if the operation crossed zero,
    ; then clamp velocity to zero.
    bmi @zero_out

    sta player_vel_x
    jmp @done

@left_friction:
    clc
    lda player_vel_x+1
    adc #<PLAYER_FRC
    sta player_vel_x+1
    lda player_vel_x
    adc #>PLAYER_FRC

    ; if the operation crossed zero,
    ; then clamp velocity to zero.
    bpl @zero_out

    sta player_vel_x
    jmp @done

@zero_out:
    lda #0
    sta player_vel_x
    sta player_vel_x+1

@done:
    rts
.endproc

; get metatile index from x and y coords
;
; in pseudocode:
; tx = player_x div 16
; ty = player_y div 16
; idx = (ty * 16) + tx
.proc metatile_get_index
    lda div16_table, x
    sta temp
    tya
    and #%11110000
    ora temp
    rts
.endproc

.proc player_horizontal_movement
    ; apply horizontal movement
    ADD16 player_x, player_vel_x

    ; detect direction
    lda player_vel_x+0
    bne :+ ; check subvelocity if necessary
        lda player_vel_x+1
        beq @fail
    :
    bpl @right_collision

@left_collision:
    lda player_x
    sec
    sbc #PLAYER_WIDTH
    tax
    ldy player_y
    jsr metatile_get_index
    tax
    lda tilemap, x
    beq :+ ; if tile is solid
        ; snap to grid
        lda player_x
        sec
        sbc #PLAYER_WIDTH
        clc
        adc #15
        and #%11110000
        clc
        adc #PLAYER_WIDTH
        sta player_x
        jmp @success
    :
    jmp @fail

@right_collision:
    lda player_x
    clc
    adc #PLAYER_WIDTH
    tax
    ldy player_y
    jsr metatile_get_index
    tax
    lda tilemap, x
    beq :+
        ; snap
        lda player_x
        clc
        adc #PLAYER_WIDTH
        and #%11110000
        sec
        sbc #PLAYER_WIDTH
        sta player_x
        jmp @success
    :
    ; jmp @fail

@fail:
    ; collision has failed
    lda #0
    jmp @done

@success:
    lda #1

@done:
    rts
.endproc

.proc player_vertical_movement
    ; apply vertical movement
    ADD16 player_y, player_vel_y

    ; detect direction
    lda player_vel_y+0
    bne :+ ; check subvelocity if necessary
        lda player_vel_y+1
        beq @fail
    :
    bpl @down_collision

@up_collision:
    ldx player_x
    lda player_y
    sec
    sbc #PLAYER_HEIGHT
    tay
    jsr metatile_get_index
    tax
    lda tilemap, x
    beq :+ ; if tile is solid
        ; snap to grid
        lda player_y
        sec
        sbc #PLAYER_HEIGHT
        clc
        adc #15
        and #%11110000
        clc
        adc #PLAYER_HEIGHT
        sta player_y
        jmp @success
    :
    jmp @fail

@down_collision:
    ldx player_x
    lda player_y
    clc
    adc #PLAYER_HEIGHT
    tay
    jsr metatile_get_index
    tax
    lda tilemap, x
    beq :+
        ; snap
        lda player_y
        clc
        adc #PLAYER_HEIGHT
        and #%11110000
        sec
        sbc #PLAYER_HEIGHT
        sta player_y
        jmp @success
    :
    ; jmp @fail

@fail:
    ; collision has failed
    lda #0
    jmp @done

@success:
    lda #1

@done:
    rts
.endproc

.proc player_apply_movement
    jsr player_gravity

    jsr player_horizontal_movement
    beq :+
        ; clear speed
        lda #0
        sta player_vel_x+0
        sta player_vel_x+1
    :

    jsr player_vertical_movement
    beq :+
        ; clear speed
        lda #0
        sta player_vel_y+0
        sta player_vel_y+1
    :

    rts
.endproc

.segment "RODATA"
PALETTE:
    .byte $0C,$15,$26,$2C
    .byte $3C,$09,$19,$29
    .byte $0F,$01,$2C,$21 ; bg2 blue
    .byte $0F,$00,$10,$30 ; bg3 greyscale
    .byte $0C,$20,$10,$00 ; sp0 yellow
    .byte $0F,$14,$24,$34 ; sp1 purple
    .byte $0F,$1B,$2B,$3B ; sp2 teal
    .byte $0F,$12,$22,$32 ; sp3 marine

tilemap:
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$01,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$01,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$01,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$01,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$01,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$01,$00,$01

    .byte $01,$00,$00,$00,$01,$01,$00,$00, $00,$00,$00,$00,$01,$00,$00,$01
    .byte $01,$00,$00,$00,$01,$01,$00,$00, $00,$00,$01,$01,$00,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$01
    .byte $01,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$01
    .byte $01,$01,$01,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$01
    .byte $01,$01,$01,$01,$01,$01,$01,$01, $01,$01,$01,$01,$01,$01,$01,$01
    .byte $01,$01,$01,$01,$01,$01,$01,$01, $01,$01,$01,$01,$01,$01,$01,$01

div16_table:
    .repeat 256, I
        .byte I / 16
    .endrep

.segment "VECTORS"
    .addr nmi_handler
    .addr reset_handler
    .addr irq_handler
    ; specialized hardware interrupts
    ;
.segment "CHARS"
    .incbin "rom.chr"
