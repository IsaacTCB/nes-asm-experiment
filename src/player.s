.include "player.inc"

.include "common.inc"
.include "main.inc"
.include "math.inc"

; ====================
;       Player
; ====================

.segment "ZEROPAGE"
collision_param1: .res $01
collision_param2: .res $02

; D1 == HIT
COLLISION_FLAGS_SOLID = %00000001
collision_flags: .res $01
collision_tile: .res $01

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
    lda $50
    beq :+
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

.macro snap_to_grid_start pos, size
    lda pos+0
    sec
    sbc size
    clc
    adc #15
    and #%11110000
    clc
    adc size
    sta pos+0
    lda #0
    sta pos+1
.endmacro

.macro snap_to_grid_end pos, size
    lda pos+0
    clc
    adc size
    and #%11110000
    sec
    sbc size
    sta pos+0
    lda #0
    sta pos+1
.endmacro

.macro get_edge_offsets var, edge_size
    lda var
    clc
    adc #(edge_size-1)
    sta collision_param2+0
    lda var
    sec
    sbc #(edge_size-1)
    sta collision_param2+1
.endmacro

.macro test_collision flipped, var, hit_label
.if flipped = 1
    ldx var
    ldy collision_param1
.else
    ldx collision_param1
    ldy var
.endif

    jsr metatile_get_index
    tax
    
    ; discover collision type
    lda tilemap, x
    bne hit_label
.endmacro

.proc player_vertical_edge
    ; check tile
    test_collision 0, collision_param2+0, @collided_with_solid
    test_collision 0, collision_param2+1, @collided_with_solid

@not_collided:
    lda #0
    sta collision_flags
    stx collision_tile
    rts
        
@collided_with_solid:
    lda #COLLISION_FLAGS_SOLID
    sta collision_flags
    stx collision_tile
    rts

.endproc

.proc player_horizontal_edge
    ; check tile
    test_collision 1, collision_param2+0, @collided_with_solid
    test_collision 1, collision_param2+1, @collided_with_solid

@not_collided:
    lda #0
    sta collision_flags
    stx collision_tile
    rts
        
@collided_with_solid:
    lda #COLLISION_FLAGS_SOLID
    sta collision_flags
    stx collision_tile
    rts

.endproc

.proc player_horizontal_movement
    ; apply horizontal movement
    ADD16 player_x, player_vel_x
    
    get_edge_offsets player_y, PLAYER_HEIGHT

    ; detect direction
    lda player_vel_x+0
    bne :+ ; check subvelocity if necessary
        lda player_vel_x+1
        beq @skip
    :
    bpl @right_collision

@left_collision:
    ; get player edge and store it in temp
    lda player_x
    sec
    sbc #PLAYER_WIDTH
    sta collision_param1
    jsr player_vertical_edge
    and #COLLISION_FLAGS_SOLID
    beq :+
        CLEAR16 player_vel_x
        snap_to_grid_start player_x, #PLAYER_WIDTH
    :
    rts

@right_collision:
    ; get player edge and store it in temp
    lda player_x
    clc
    adc #PLAYER_WIDTH
    sta collision_param1
    jsr player_vertical_edge
    and #COLLISION_FLAGS_SOLID
    beq :+
        CLEAR16 player_vel_x
        snap_to_grid_end player_x, #PLAYER_WIDTH
    :
    
@skip:
    rts
.endproc

.proc player_vertical_movement
    ; apply vertical movement
    ADD16 player_y, player_vel_y
    
    get_edge_offsets player_x, PLAYER_WIDTH

    ; detect direction
    lda player_vel_y+0
    bne :+ ; check subvelocity if necessary
        lda player_vel_y+1
    :
    bpl @down_collision

@up_collision:
    ; get player edge and store it in temp
    lda player_y
    sec
    sbc #PLAYER_HEIGHT
    sta collision_param1
    jsr player_horizontal_edge
    and #COLLISION_FLAGS_SOLID
    beq :+
        CLEAR16 player_vel_y
        snap_to_grid_start player_y, #PLAYER_HEIGHT
    :
    ; not grounded
    lda #0
    sta $50
    rts

@down_collision:
    ; get player edge and store it in temp
    lda player_y
    clc
    adc #PLAYER_HEIGHT
    sta collision_param1
    jsr player_horizontal_edge
    and #COLLISION_FLAGS_SOLID
    beq :+
        CLEAR16 player_vel_y
        snap_to_grid_end player_y, #PLAYER_HEIGHT
        ; flag as grounded
        lda #1
        sta $50
        jmp @skip
    :
    ; not grounded
    lda #0
    sta $50
    
@skip:
    rts
.endproc

.proc player_apply_movement
    jsr player_gravity

    jsr player_horizontal_movement

    jsr player_vertical_movement
    beq :+
        CLEAR16 player_vel_y
    :

    rts
.endproc

player_metasprite:
    ;     X    Y    Tile Attr
    .byte $F8, $F7, $00, $00
    .byte $00, $F7, $01, $00
    .byte $F8, $FF, $10, $00
    .byte $00, $FF, $11, $00
    .byte $80 ; end

; A -> oam sprite index
; draw_pos[0] -> x coords
; draw_pos[1] -> y coords
.proc player_draw_sprite
    asl a
    asl a
    tax

    ; u8 y = 0;
    ; while (player_metasprite[y] == 0x80) {
    ;
    ;    OAM[x+0] = draw_y + player_metasprite[y+1];
    ;    OAM[x+1] = player_metasprite[y+2];
    ;    OAM[x+2] = player_metasprite[y+3];
    ;    OAM[x+3] = draw_x + player_metasprite[y+0];
    ;
    ;    x += 4;
    ;    y += 4;
    ; }

    ldy #0
@copy_sprite:
    ; check for breakpoint sentinel ($80)
    lda player_metasprite, y
    cmp #$80
    beq @break

    ; sprite y
    lda draw_pos + 1
    clc
    adc player_metasprite + 1, y
    sta OAM, x
    inx
    ; sprite tile
    lda player_metasprite + 2, y
    sta OAM, x
    inx
    ; sprite attr
    lda player_metasprite + 3, y
    sta OAM, x
    inx
    ; sprite x
    lda draw_pos + 0
    clc
    adc player_metasprite + 0, y
    sta OAM, x
    inx

    ; keep going
    iny
    iny
    iny
    iny
    jmp @copy_sprite

@break:
    rts
.endproc
