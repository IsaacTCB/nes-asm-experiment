.include "player.inc"

.include "common.inc"
.include "main.inc"
.include "math.inc"

; ====================
;       Player
; ====================

.segment "CODE"

.proc player_update
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
    checkbtn_pressed #PAD_A
    beq :+
        STORE16 player_vel_y, #$FC00
    :

    ; fly
    checkbtn #PAD_B
    beq :+
        STORE16 player_vel_y, #$FD00
    :

    lda player_input_dir
    beq @player_friction
    bpl @player_move_right

@player_move_left:
    SUB16 player_vel_x, #PLAYER_ACC
    jmp @player_done

@player_move_right:
    ADD16 player_vel_x, #PLAYER_ACC
    jmp @player_done

@player_friction:
    jsr player_apply_friction
    jmp @player_done

@player_done:
    jsr player_apply_movement

    rts
.endproc

.proc player_gravity
    ADD16 player_vel_y, #PLAYER_GRV

    ; verify sign
    lda player_vel_y
    bpl @moving_down

; ------------------------
;    Clamp up direction
; ------------------------
@moving_up:
    lda player_vel_y + 0
    cmp #>PLAYER_MIN_VSP
    bcc @clamp_up_velocity
    bne @done

    lda player_vel_y + 1
    cmp #<PLAYER_MIN_VSP
    bcc @clamp_up_velocity
    jmp @done

@clamp_up_velocity:
    STORE16 player_vel_y, #PLAYER_MIN_VSP
    rts

; ------------------------
;   Clamp down direction
; ------------------------
@moving_down:
    lda player_vel_y + 0
    cmp #>PLAYER_MAX_VSP
    bcc @done
    bne @clamp_down_velocity

    lda player_vel_y + 1
    cmp #<PLAYER_MAX_VSP
    bcc @done
    beq @done

@clamp_down_velocity:
    STORE16 player_vel_y, #PLAYER_MAX_VSP

@done:
    rts
.endproc

.proc player_apply_friction
    ; if velocity is exactly 0, do nothing.
    lda player_vel_x
    bne @check_sign
    lda player_vel_x+1
    beq @done

@check_sign:
    bmi @left_friction

@right_friction:
    SUB16 player_vel_x, #PLAYER_FRC

    ; if the operation crossed zero,
    ; then clamp velocity to zero.
    bmi @zero_out
    jmp @done

@left_friction:
    ADD16 player_vel_x, #PLAYER_FRC

    ; if the operation crossed zero,
    ; then clamp velocity to zero.
    bpl @zero_out
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
        lda player_x+0
        sec
        sbc #PLAYER_WIDTH
        clc
        adc #15
        and #%11110000
        clc
        adc #PLAYER_WIDTH
        sta player_x+0
        lda #0
        sta player_x+1
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
        lda player_x+0
        clc
        adc #PLAYER_WIDTH
        and #%11110000
        sec
        sbc #PLAYER_WIDTH
        sta player_x+0
        lda #0
        sta player_x+1
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
        lda player_y+0
        sec
        sbc #PLAYER_HEIGHT
        clc
        adc #15
        and #%11110000
        clc
        adc #PLAYER_HEIGHT
        sta player_y+0
        lda #0
        sta player_y+1
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
        lda player_y+0
        clc
        adc #PLAYER_HEIGHT
        and #%11110000
        sec
        sbc #PLAYER_HEIGHT
        sta player_y+0
        lda #0
        sta player_y+1
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
        CLEAR16 player_vel_x
    :

    jsr player_vertical_movement
    beq :+
        CLEAR16 player_vel_y
    :

    rts
.endproc

; A -> oam sprite index
; draw_pos[0] -> x coords
; draw_pos[1] -> y coords
.proc player_draw_sprite
    asl a
    asl a
    tax
    ; y coord
    lda draw_pos+1
    sec
    sbc #10
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
