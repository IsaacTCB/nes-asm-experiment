.ifndef _PLAYER_INC
.define _PLAYER_INC

; ------------------
;    Subroutines
; ------------------

.global player_update
.global player_draw_sprite

; ------------------
;     Constants
; ------------------

; Movement

PLAYER_ACC = $0040
PLAYER_FRC = $0020
PLAYER_GRV = $0020

PLAYER_MAX_VSP = $0700
PLAYER_MIN_VSP = (-PLAYER_MAX_VSP)

; Collision

PLAYER_WIDTH = 6
PLAYER_HEIGHT = 7

.endif ; _PLAYER_INC
