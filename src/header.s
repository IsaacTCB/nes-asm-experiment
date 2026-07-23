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
