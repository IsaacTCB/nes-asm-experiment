.include "main.inc"

.include "common.inc"
.include "math.inc"
.include "player.inc"

; NES 2.0 header
.segment "HEADER"
    .byte "NES" ; id string
    .byte $1A
    .byte $02   ; amount of PRG ROM in 16K units
    .byte $01   ; amount of CHR ROM in 8k units
    .byte $00   ; mapper and mirroing
    .byte $08, $00, $00, $00
    .byte $00, $00, $00, $00
    .byte $01   ; intended default controller

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

.macro wait_for_vblank
    :
        BIT $2002
        BPL :-
.endmacro

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
    sta $0000, x
    sta $0100, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    lda #$FE
    sta $0200, x
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

    ; update & draw player
    jsr player_update
    lda player_x
    sta draw_pos+0
    lda player_y
    sta draw_pos+1
    lda #1
    jsr player_draw_sprite

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

.segment "RODATA"
PALETTE:
    .byte $0C,$15,$26,$2C
    .byte $3C,$09,$19,$29
    .byte $0F,$01,$2C,$21
    .byte $0F,$00,$10,$30
    .byte $0C,$20,$10,$00
    .byte $0F,$14,$24,$34
    .byte $0F,$1B,$2B,$3B
    .byte $0F,$12,$22,$32

.global tilemap
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

.global div16_table
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
