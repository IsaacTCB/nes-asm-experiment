.ifndef _CART_INC
.define _CART_INC

.macro wait_for_vblank
    :
        BIT $2002
        BPL :-
.endmacro

.endif ; _CART_INC
