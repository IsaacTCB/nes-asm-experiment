.ifndef _MATH_INC
.define _MATH_INC

.macro STORE16 position, arg1
.if (.match (.left (1, {arg1}), #))
    lda #>(.right (.tcount ({arg1})-1, {arg1}))
    sta position+0
    lda #<(.right (.tcount ({arg1})-1, {arg1}))
    sta position+1
.else
    lda arg1+0
    sta position+0
    lda arg1+1
    sta position+1
.endif
.endmacro

.macro CLR16 position
    lda #0
    sta position+0
    sta position+1
.endmacro

.macro ADD16 position, arg1
.if (.match (.left (1, {arg1}), #))
    lda position+1
    clc
    adc #<(.right (.tcount ({arg1})-1, {arg1}))
    sta position+1
    lda position+0
    adc #>(.right (.tcount ({arg1})-1, {arg1}))
    sta position+0
.else
    lda position+1
    clc
    adc arg1+1
    sta position+1
    lda position+0
    adc arg1+0
    sta position+0
.endif
.endmacro

.macro SUB16 position, arg1
.if (.match (.left (1, {arg1}), #))
    lda position+1
    sec
    sbc #<(.right (.tcount ({arg1})-1, {arg1}))
    sta position+1
    lda position+0
    sbc #>(.right (.tcount ({arg1})-1, {arg1}))
    sta position+0
.else
    lda position+1
    sec
    sbc arg1+1
    sta position+1
    lda position+0
    sbc arg1+0
    sta position+0
.endif
.endmacro

.endif ; _MATH_INC
