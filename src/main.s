.include "main.inc"
.include "common.inc"

PLAYER_ACC = $0020

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
    player_x: .res $02
    player_y: .res $02
    player_vel_x: .res $02
    player_vel_y: .res $02
    scroll_x: .res $01
    scroll_y: .res $01

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

    lda #24
    sta player_x
    lda #16
    sta player_y

@loop:
    jsr ppu_wait

    jsr poll_gamepad

    lda nmi_frame
    and #$03
    bne :+
    inc scroll_x
    inc scroll_y
    :

    lda buttons
    and #PAD_L
    beq :+
        jsr player_move_left
    :

    lda buttons
    and #PAD_R
    beq :+
        jsr player_move_right
    :

    lda buttons
    and #PAD_U
    beq :+
        jsr player_move_up
    :

    lda buttons
    and #PAD_D
    beq :+
        jsr player_move_down
    :

    jsr player_apply_movement

    lda player_x
    sta draw_pos+0
    lda player_y
    sta draw_pos+1
    lda #1
    jsr draw_player_sprite

    lda draw_pos+1
    clc
    adc #14
    sta draw_pos+1
    lda #5
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
    ; x coord
    lda draw_pos+1
    sec
    sbc #4
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

    ; y coord
    lda draw_pos+0
    sec
    sbc #4
    sta OAM+0, x
    sta OAM+8, x
    clc
    adc #8
    sta OAM+4, x
    sta OAM+12, x

    rts
.endproc

; updates zeropage variable 'buttons'
.proc poll_gamepad
    ; strobe the gamepad to latch current button state
	lda #1
	sta GAMEPAD1
	lda #0
	sta GAMEPAD1
	; read 8 bytes from the interface at $4016
	ldx #8
	:
		pha
		lda GAMEPAD1
		; combine low two bits and store in carry bit
		and #%00000011
		cmp #%00000001
		pla
		; rotate carry into gamepad variable
		ror
		dex
		bne :-
	sta buttons
	rts
.endproc

.proc load_background
    ldy #0
@copy_bg_1:
    ldx #0
@copy_bg_2:
    lda #$00
    sta $2007
    sta $2007
    lda #$FF
    sta $2007
    sta $2007
    inx
    cpx #16
    bne @copy_bg_2

    ldx #0
@copy_bg_3:
    lda #$FF
    sta $2007
    sta $2007
    lda #$00
    sta $2007
    sta $2007
    inx
    cpx #16
    bne @copy_bg_3

    iny
    cpy #7
    bne @copy_bg_1

@copy_bg_4:


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

.proc player_move_up
    lda player_vel_y+1
    sec
    sbc #<PLAYER_ACC
    sta player_vel_y+1
    lda player_vel_y+0
    sbc #>PLAYER_ACC
    sta player_vel_y+0
    rts
.endproc

.proc player_move_down
    lda player_vel_y+1
    clc
    adc #<PLAYER_ACC
    sta player_vel_y+1
    lda player_vel_y+0
    adc #>PLAYER_ACC
    sta player_vel_y+0
    rts
.endproc

.proc player_apply_movement
    ; horizontal movement
    lda player_x+1
    clc
    adc player_vel_x+1
    sta player_x+1
    lda player_x+0
    adc player_vel_x+0
    sta player_x+0

    ; vertical movement
    lda player_y+1
    clc
    adc player_vel_y+1
    sta player_y+1
    lda player_y+0
    adc player_vel_y+0
    sta player_y+0

    rts
.endproc

.segment "RODATA"
PALETTE:
    .byte $30,$15,$26,$31
    .byte $3C,$09,$19,$29
    .byte $0F,$01,$11,$21 ; bg2 blue
    .byte $0F,$00,$10,$30 ; bg3 greyscale
    .byte $30,$20,$10,$00 ; sp0 yellow
    .byte $0F,$14,$24,$34 ; sp1 purple
    .byte $0F,$1B,$2B,$3B ; sp2 teal
    .byte $0F,$12,$22,$32 ; sp3 marine

.segment "VECTORS"
    .addr nmi_handler
    .addr reset_handler
    .addr irq_handler
    ; specialized hardware interrupts
    ;
.segment "CHARS"
    .incbin "rom.chr"
