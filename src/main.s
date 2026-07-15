.include "main.inc"
.include "common.inc"

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

    ; enable interrupts and start nmi
    cli
    lda #%10010000
    sta $2000

@loop:
    jsr ppu_wait

    ldx nmi_frame
    cmp #50
    bne :+
    jsr ppu_stop
:
    jmp @loop

.endproc

.export irq_handler
.proc irq_handler
    RTI
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
    lda #0
    sta $2005
    sta $2005

    ; enable rendering
	lda #%00011110
	sta $2001

    lda #%00
    sta ppu_ready

@ppu_update_end:
    rts
.endproc

.segment "CODE"
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

.segment "RODATA"
PALETTE:
    .byte $3C,$15,$26,$37 ; bg0 purple/pink
    .byte $3C,$09,$19,$29 ; bg1 green
    .byte $0F,$01,$11,$21 ; bg2 blue
    .byte $0F,$00,$10,$30 ; bg3 greyscale
    .byte $32,$20,$30,$38 ; sp0 yellow
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
