; =============================================================================================
;  Project Moon Pi intro -- loader: a BASIC line, the unpacker, and the packed intro.
;  LOAD"MOON PI INTRO",8 then RUN. The packed data moves up to end at $c000, the unpacker moves to the
;  cassette buffer ($0334), then everything unpacks into place ($c000-$ffbf incl. under the I/O area,
;  and $0800 up) and the intro starts at $0800. Format: see tools/pack.py.
;  Designed and Created by Project Moon Pi.
; =============================================================================================

!cpu 6510
!to "build/moonpi-intro.prg", cbm
!source "build/pack.inc"

src     = $fb
dst     = $fd
ref     = $f7
len     = $f9
tmp     = $fa
DEP     = $0334

        * = $0801
        !word +, 2026
        !byte $9e
        !text "2061"
        !byte 0
+       !word 0

        sei
        ldx #0                          ; the unpacker to the cassette buffer
-       lda dep_src,x
        sta DEP,x
        inx
        cpx #dep_end-dep_src
        bne -

        ; move the packed data up so it ends at $c000 (highest bytes first: the areas overlap)
        lda #<(packed + PSIZE - 256)
        sta src
        lda #>(packed + PSIZE - 256)
        sta src+1
        lda #<($c000 - 256)
        sta dst
        lda #>($c000 - 256)
        sta dst+1
        ldx #>PSIZE                     ; whole pages
        beq .rest
.page   ldy #$ff
-       lda (src),y
        sta (dst),y
        dey
        cpy #$ff
        bne -
        dec src+1
        dec dst+1
        dex
        bne .page
.rest   lda #<packed                    ; the part page at the very start
        sta src
        lda #>packed
        sta src+1
        lda #<($c000 - PSIZE)
        sta dst
        lda #>($c000 - PSIZE)
        sta dst+1
        ldy #<PSIZE
        beq +
-       dey
        lda (src),y
        sta (dst),y
        cpy #0
        bne -
+       jmp DEP

dep_src
!pseudopc DEP {
        lda #<($c000 - PSIZE)
        sta src
        lda #>($c000 - PSIZE)
        sta src+1
        lda #$34                        ; all RAM, even $d000-$dfff
        sta $01
.seg    jsr getb
        sta dst
        jsr getb
        sta dst+1
        bne .tok
        lda #$37
        sta $01
        jmp $0800                       ; the intro
.tok    jsr getb
        bmi .match
        tax                             ; literals
        inx
.lit    jsr getb
        ldy #0
        sta (dst),y
        inc dst
        bne +
        inc dst+1
+       dex
        bne .lit
        beq .tok
.match  cmp #$ff
        beq .seg
        cmp #$c0
        bcs .long
        and #$3f                        ; near copy
        clc
        adc #2
        sta len
        jsr getb
        eor #$ff
        clc
        adc dst
        sta ref
        lda #$ff
        adc dst+1
        sta ref+1
        jmp .copy
.long   and #$3f                        ; far copy
        clc
        adc #3
        sta len
        jsr getb
        sta tmp
        jsr getb
        tax
        lda dst
        sec
        sbc tmp
        sta ref
        stx tmp
        lda dst+1
        sbc tmp
        sta ref+1
.copy   ldy #0
-       lda (ref),y
        sta (dst),y
        iny
        cpy len
        bne -
        tya
        clc
        adc dst
        sta dst
        bcc .tok
        inc dst+1
        jmp .tok
getb    ldy #0
        lda (src),y
        inc src
        bne +
        inc src+1
+       ora #0
        rts
}
dep_end
        !if dep_end - dep_src > $cc { !error "unpacker too big for the cassette buffer" }

packed  !binary "build/packed.bin"
