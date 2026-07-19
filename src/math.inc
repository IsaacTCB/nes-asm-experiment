.ifndef _MATH_INC
.define _MATH_INC

.macro STORE16 short, arg
.if (.match (.left (1, {arg}), #))
    .define VALUE .right (.tcount ({arg})-1, {arg})
    .if .const(VALUE) .and ((>VALUE) = (<VALUE))
        ; micro-optimization: if upper bytes and lower
        ; bytes are the same, then just load once.
        lda #>VALUE
        sta short+0
        sta short+1
    .else
        lda #>VALUE
        sta short+0
        lda #<VALUE
        sta short+1
    .endif
    .undef VALUE
.else
    lda arg+0
    sta short+0
    lda arg+1
    sta short+1
.endif
.endmacro

.macro CLEAR16 short
    STORE16 short, $0000
.endmacro

.macro ADD16 short, arg
.if (.match (.left (1, {arg}), #))
    lda short+1
    clc
    adc #<(.right (.tcount ({arg})-1, {arg}))
    sta short+1
    lda short+0
    adc #>(.right (.tcount ({arg})-1, {arg}))
    sta short+0
.else
    lda short+1
    clc
    adc arg+1
    sta short+1
    lda short+0
    adc arg+0
    sta short+0
.endif
.endmacro

.macro SUB16 short, arg
.if (.match (.left (1, {arg}), #))
    lda short+1
    sec
    sbc #<(.right (.tcount ({arg})-1, {arg}))
    sta short+1
    lda short+0
    sbc #>(.right (.tcount ({arg})-1, {arg}))
    sta short+0
.else
    lda short+1
    sec
    sbc arg+1
    sta short+1
    lda short+0
    sbc arg+0
    sta short+0
.endif
.endmacro

.endif ; _MATH_INC
