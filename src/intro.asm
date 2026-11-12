; =============================================================================================
;  Project Moon Pi -- animated logo intro for the Commodore 64 (NTSC, 6567R8 VIC: 65 cycles a line)
;
;  The website intro, rebuilt to push the machine:
;    - a starfield streams out of the middle (plotted pixels), the badge flies in flipping like a coin
;      (up to six multicolour sprites, double-buffered), all in VIC bank 2;
;    - it lands with a white flash and a sideways jolt, and the screen switches to VIC bank 3, where the
;      badge waits as an FLI picture: 172 lines tall, new colours on every line (a forced bad line on
;      each of 176 raster lines, timed to the cycle);
;    - sparks fly, a flare runs round the ring and bursts at the tip, ring stars twinkle, the engine
;      flames flicker, "DESIGNED AND CREATED BY / PROJECT MOON PI" fades in (C64 character set, hires);
;    - an old-TV switch-off ends it (each line flipped to an invalid VIC mode, which shows black).
;  The SID plays a gliding chord, then a bell strike and a drum on the starburst.
;  Any key or fire button skips it. At the end the machine resets to BASIC.
;
;  This file assembles to build/main.bin (loads at $0800). tools/pack.py packs it together with
;  build/fli.bin ($c000-$ffbf) behind src/loader.asm. See build.sh.
;  Designed and Created by Project Moon Pi.
; =============================================================================================

!cpu 6510
!to "build/main.bin", plain

; ---- memory -------------------------------------------------------------------------------------
SCR2    = $8000         ; bank 2: screen colours (starfield), sprite pointers at $83f8
SPRA    = $8400         ; bank 2: coin sprites, buffer A (blocks 16-21)
SPRB    = $8580         ; bank 2: coin sprites, buffer B (blocks 22-27)
FONT    = $8800         ; the character ROM's first 64 characters
BMP2    = $a000         ; bank 2: starfield bitmap
FLI     = $c000         ; bank 3: eight screens ($c000-$dfff), then the bitmap
BMP3    = $e000
COLRAM  = $d800

st_dlo  = $8a00         ; star state
st_dhi  = $8a20
st_ang  = $8a40
st_oldl = $8a60
st_oldh = $8a80
st_oldm = $8aa0

; ---- zero page (we never go back to BASIC, so it is all ours) --------------------------------
frame   = $02           ; 16-bit, counted by the bottom interrupt
f       = $04           ; 16-bit, the frame the main loop is working on
ma      = $06
mb      = $07
mlo     = $08
mhi     = $09
ptr     = $0a
ptr2    = $0c
t1      = $0e
t2      = $0f
si      = $10
r       = $11
xs      = $12           ; 16-bit
ys      = $14
cell    = $15           ; 16-bit
mus     = $17           ; 16-bit
dirty   = $19
logo_on = $1a
buf     = $1b
lastfid = $1c
armed   = $1d
rndi    = $1e
landed  = $1f
outclr  = $20
warp    = $21
idx     = $22
nx      = $23
cnt     = $24
col     = $25
cx      = $26           ; 16-bit
cy      = $28
dxx     = $29
dyy     = $2a
msb     = $2b
pbase   = $2c
lastf   = $2d
dst     = $2e           ; 16-bit
gl      = $30           ; 16-bit
k       = $32
fcol    = $33
bmbase  = $34           ; high byte of the bitmap the stars go into
nstar   = $35
fli_on  = $36
sh_bank = $37           ; $dd00 low bits: 1 = bank 2, 0 = bank 3
curh    = $38           ; TV switch-off: half the picture height still showing
lastc1  = $39
lastc2  = $3a
drawn   = $3c
d016b   = $3b           ; $d016 bits for the credit rows: $08 hires, $18 multicolour (during the flash)
app_y6  = $70           ; sprite 6/7 state as last written to the VIC (for the FLI timing patch)
app_y7  = $71
app_en  = $72
app_ye  = $73
n6lo    = $74           ; FLI lines each sprite covers (lo..hi-1), now and last time
n6hi    = $75
n7lo    = $76
n7hi    = $77
o6lo    = $78
o6hi    = $79
o7lo    = $7a
o7hi    = $7b
q1      = $7c           ; interrupt-only scratch (spfix runs inside the FLI interrupt)
q2      = $7d
qsi     = $7e
qcnt    = $7f
qptr    = $80           ; 16-bit

sh_x    = $40           ; shadow VIC registers, copied in the bottom interrupt when dirty
sh_y    = $48
sh_ptr  = $50
sh_col  = $58
sh_msb  = $60
sh_en   = $61
sh_mc   = $62
sh_xe   = $63
sh_ye   = $64
sh_mc0  = $65
sh_mc1  = $66
sh_d011 = $67
sh_xs   = $68
sh_bord = $69
sh_bg   = $6a

FLI_LINES = 176         ; FLI raster lines (character rows 0-21)
LL      = 16            ; bytes of FLI code per line (16 lines a page)
MID     = FLI_LINES / 2
!ifndef K6 { K6 = 2 }    ; delay patches (see spfix), measured in VICE x64sc NTSC
!ifndef K7 { K7 = 2 }
!ifndef K67 { K67 = 3 }
!ifndef CAL { CAL = 0 }  ; 1: calibration -- sprites 6/7 parked at fixed heights after the landing

        * = $0800

; =============================================================================================
start   sei
        lda #$7f                        ; no CIA interrupts
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #0
        sta $d01a
        sta $d015
        sta $d020
        sta $d021
        lda #$0b                        ; screen off while we set up
        sta $d011
        lda #$ff
        sta $d019

        lda #$33                        ; character ROM in: copy the first 64 characters
        sta $01
        ldx #0
-       lda $d000,x
        sta FONT,x
        lda $d100,x
        sta FONT+$100,x
        inx
        bne -
        lda #$35                        ; all RAM but I/O from here on
        sta $01
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb

        ldx #$18                        ; SID quiet
        lda #0
-       sta $d400,x
        dex
        bpl -

        lda #<BMP2                      ; clear the bank 2 bitmap and screen, colour RAM
        sta ptr
        lda #>BMP2
        sta ptr+1
        ldx #32
        ldy #0
        tya
-       sta (ptr),y
        iny
        bne -
        inc ptr+1
        dex
        bne -
        ldx #0
-       sta SCR2,x
        sta SCR2+$100,x
        sta SCR2+$200,x
        sta SCR2+$300,x
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$300,x
        inx
        bne -

        ldx #NST-1                      ; stars
-       lda s_dhi,x
        sta st_dhi,x
        lda s_ang,x
        sta st_ang,x
        lda #0
        sta st_dlo,x
        sta st_oldh,x
        dex
        bpl -

        lda #0                          ; variables and shadows
        ldx #$7f
-       sta $02,x
        dex
        bpl -
        lda #$ff
        sta lastfid
        sta lastf
        sta lastc1
        sta lastc2
        lda #$3b
        sta sh_d011
        lda #6
        sta sh_mc0
        lda #14
        sta sh_mc1
        lda #>BMP2
        sta bmbase
        lda #NST
        sta nstar
        lda #1
        sta sh_bank
        lda #MID
        sta curh
        lda #$18
        sta d016b
        lda #255
        sta o6lo
        sta o7lo
        lda #<music
        sta mus
        lda #>music
        sta mus+1

        lda $dd00                       ; VIC bank 2
        and #$fc
        ora #1
        sta $dd00
        lda #$08                        ; screen +$0000, bitmap +$2000
        sta $d018
        lda #$18
        sta $d016
        lda #251
        sta $d012
        lda #$3b
        sta $d011
        lda #1
        sta $d01a
        sta dirty
        lda #$ff
        sta $d019
        cli

; =============================================================================================
;  main loop: once per frame
; =============================================================================================
main    lda frame
        cmp lastf
        beq main
        sta lastf
        sta f
        lda frame+1
        sta f+1
        jsr skipkey
        bcc +
        jmp finish
+       lda f+1                         ; the end?
        cmp #>END
        bcc +
        bne ++
        lda f
        cmp #<END
        bcc +
++      jmp finish

+       ldx f                           ; warp for this frame
        lda f+1
        bne +
        lda warp_lo,x
        jmp ++
+       lda warp_hi,x
++      sta warp

        lda f+1                         ; stars, until the switch-off
        cmp #>OUT
        bcc +
        bne ++
        lda f
        cmp #<OUT
        bcs ++
+       jsr stars
++
        lda f+1                         ; coin until FACE, then the landing, then the show
        bne +
        lda f
        cmp #FACE
        bcs +
        jsr coin
        jmp done
+       lda landed
        bne +
        jsr land
+       jsr post
done    lda #1
        sta dirty
        jmp main

; ---- any key or fire button skips (only after everything was let go once) -------------------
skipkey lda #0
        sta $dc00
        lda $dc01
        cmp #$ff
        bne .down
        lda #$ff
        sta $dc00
        lda $dc00
        and #$10
        beq .down
        lda #1
        sta armed
        clc
        rts
.down   lda armed
        beq +
        sec
        rts
+       clc
        rts

; =============================================================================================
;  interrupts
; =============================================================================================
irq     pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019
        lda $d012
        cmp #128
        bcs irqb
        jmp irqa

; ---- bottom of the screen (line 251), before the FLI starts: per-frame work, then line 251 again
irqb    lda sh_xs
        ora #$18
        sta $d016
        jsr ftasks
        lda fli_on
        beq +
        lda #46                         ; FLI from the next frame
        bne ++
+       lda #251
++      sta $d012
        jmp irqout

; ---- once a frame: shadow registers to the VIC, sprite pointers, FLI timing patch, music --------
ftasks  lda dirty
        bne +
        jmp .nocopy
+       ldx #7
-       txa
        asl
        tay
        lda sh_x,x
        sta $d000,y
        lda sh_y,x
        sta $d001,y
        lda sh_col,x
        sta $d027,x
        dex
        bpl -
        lda sh_msb
        sta $d010
        lda sh_mc
        sta $d01c
        lda sh_xe
        sta $d01d
        lda sh_ye
        sta $d017
        sta app_ye
        lda sh_mc0
        sta $d025
        lda sh_mc1
        sta $d026
        lda sh_en
        sta $d015
        sta app_en
        lda sh_y+6
        sta app_y6
        lda sh_y+7
        sta app_y7
        lda sh_d011
        and #$7f
        sta $d011
        lda sh_bord
        sta $d020
        lda sh_bg
        sta $d021
        lda $dd00
        and #$fc
        ora sh_bank
        sta $dd00
        lda sh_bank
        beq .fliptr
        ldx #7                          ; bank 2: one set of sprite pointers
-       lda sh_ptr,x
        sta SCR2+$3f8,x
        dex
        bpl -
        jmp .ptrok
.fliptr ldx #7                          ; bank 3: the same pointers in all eight FLI screens
-       lda sh_ptr,x                    ; (only when they change: four screens sit under I/O)
        cmp lastptr,x
        bne +
        dex
        bpl -
        jmp .patch
+       lda #$34
        sta $01
        ldx #7
-       lda sh_ptr,x
        sta lastptr,x
        sta FLI+$03f8,x
        sta FLI+$07f8,x
        sta FLI+$0bf8,x
        sta FLI+$0ff8,x
        sta FLI+$13f8,x
        sta FLI+$17f8,x
        sta FLI+$1bf8,x
        sta FLI+$1ff8,x
        dex
        bpl -
        lda #$35
        sta $01
.patch  lda fli_on                      ; FLI timing for exactly these sprites
        beq .ptrok
        jsr spfix
.ptrok  lda #0
        sta dirty
.nocopy jsr playmus
        inc frame
        bne +
        inc frame+1
+       rts

lastptr !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff

irqout  pla
        tay
        pla
        tax
        pla
nmi     rti

; ---- the FLI display (line 46 to 227) --------------------------------------------------------
;  Every line from 52 on gets a forced bad line: its $d011 write sets the vertical scroll to the
;  line's own low three bits at cycle 15, so the VIC fetches a fresh line of colours (from the
;  screen $d018 just picked) without restarting the bitmap row. The CPU then waits out the
;  40-cycle fetch and comes back at cycle 55 -- every line resynchronises itself.
irqa    lda sh_xs
        ora #$18                        ; multicolour for the badge
        sta $d016
        lda sh_xs
        ora d016b
        tay                             ; credit rows: hires (multicolour while it flashes)
        ldx #0                          ; (the delay instructions use $ea,x: keep X at 0)
        lda #$08
        sta $d018
op0     lda #$3b                        ; line 0 (a natural bad line); the switch-off sets bit 6
        sta $d011
        lda #51
-       cmp $d012
        bne -
        nop                             ; be caught by line 51's bad line
        nop
        nop
        nop
        nop
        nop
        jmp fli_lines

;  One line, 16 bytes, cycle by cycle from the end of the bad line (cycle 55):
;    lda #screen / sta $d018 / lda #$d011 / bne +k / dec $ea,x (6) / inc $ea (5) / sta $d011
;  With k = 0 the $d011 write lands on cycle 15 of the next line. Sprites fetched on that line
;  steal cycles first, so spfix sets k to 1-4 there (4, 6, 9 or 11 cycles less waiting).
;  The code is page-aligned so no branch crosses a page.
        !align 255, 0
fli_lines
        !for y, 1, FLI_LINES-1 {
        lda #((y & 7) << 4) | $08
        sta $d018
        lda #$38 | ((y + 3) & 7)
        bne + 
+       dec $ea,x
        inc $ea
        sta $d011
        }
        sty $d016                       ; credit rows: screen 0, normal bad lines
        lda #$08
        sta $d018
        lda #$3b
        sta $d011
        jsr ftasks                      ; the frame's work, with time to spare before line 46
        lda #46
        sta $d012
        jmp irqout

op_lo   !byte <(op0+1)
        !for y, 1, FLI_LINES-1 { !byte <(fli_lines + (y-1)*LL + 6) }
op_hi   !byte >(op0+1)
        !for y, 1, FLI_LINES-1 { !byte >(fli_lines + (y-1)*LL + 6) }
dl_lo   !byte <spare
        !for y, 1, FLI_LINES-1 { !byte <(fli_lines + (y-1)*LL + 8) }
dl_hi   !byte >spare
        !for y, 1, FLI_LINES-1 { !byte >(fli_lines + (y-1)*LL + 8) }
spare   !byte 0
ktab    !byte 0, K6, K7, K67            ; delay patch for: no sprite, sprite 6, sprite 7, both

; ---- spfix: patch the FLI delays for the lines sprites 6 and 7 cover --------------------
spfix   lda app_en                      ; sprite 6
        and #$40
        ldx #21
        lda app_ye
        and #$40
        beq +
        ldx #42
+       lda app_en
        and #$40
        beq +
        lda app_y6
        jsr range
        jmp ++
+       lda #255
        sta q1
        lda #0
        sta q2
++      lda q1
        sta n6lo
        lda q2
        sta n6hi
        ldx #21                         ; sprite 7
        lda app_ye
        and #$80
        beq +
        ldx #42
+       lda app_en
        and #$80
        beq +
        lda app_y7
        jsr range
        jmp ++
+       lda #255
        sta q1
        lda #0
        sta q2
++      lda q1
        sta n7lo
        lda q2
        sta n7hi
        lda n6lo                        ; lines to look at: old and new together
        cmp n7lo
        bcc +
        lda n7lo
+       cmp o6lo
        bcc +
        lda o6lo
+       cmp o7lo
        bcc +
        lda o7lo
+       sta qsi
        lda n6hi
        cmp n7hi
        bcs +
        lda n7hi
+       cmp o6hi
        bcs +
        lda o6hi
+       cmp o7hi
        bcs +
        lda o7hi
+       sta qcnt
.fl     ldy qsi
        cpy qcnt
        bcs .fdone
        lda #0
        cpy n6lo
        bcc +
        cpy n6hi
        bcs +
        ora #1
+       cpy n7lo
        bcc +
        cpy n7hi
        bcs +
        ora #2
+       tax
        lda dl_lo,y
        sta qptr
        lda dl_hi,y
        sta qptr+1
        lda ktab,x
        ldy #0
        sta (qptr),y
        inc qsi
        jmp .fl
.fdone  lda n6lo
        sta o6lo
        lda n6hi
        sta o6hi
        lda n7lo
        sta o7lo
        lda n7hi
        sta o7hi
        rts

range   ; A = sprite Y register, X = height -> q1..q2-1 = FLI lines it covers (255/0 if none)
        sec
        sbc #50
        bcc .above
        cmp #FLI_LINES
        bcs .none
        sta q1
        txa
        clc
        adc q1
        cmp #FLI_LINES
        bcc +
        lda #FLI_LINES
+       sta q2
        lda q1                          ; lines 0 and 1 are never patched (line 1 starts
        cmp #2                          ; with a little jitter, which only makes it later)
        bcs +
        lda #2
        sta q1
        cmp q2
        bcs .none
+       rts
.above  eor #$ff                        ; starts above line 0 by (50 - Y)
        clc
        adc #1
        sta q1
        txa
        sec
        sbc q1
        bcc .none
        cmp #3
        bcc .none
        sta q2
        lda #2
        sta q1
        rts
.none   lda #255
        sta q1
        lda #0
        sta q2
        rts

; ---- music: per frame a count, then that many (register, value) pairs; $ff ends it ---------
playmus ldy #0
        lda (mus),y
        cmp #$ff
        beq .mdone
        tax
        iny
.ml     cpx #0
        beq .mend
        lda (mus),y
        sta .mst+1
        iny
        lda (mus),y
.mst    sta $d400
        iny
        dex
        jmp .ml
.mend   tya
        clc
        adc mus
        sta mus
        bcc .mdone
        inc mus+1
.mdone  rts

; =============================================================================================
;  multiply: A * Y -> mlo/mhi (unsigned, quarter squares)
; =============================================================================================
mul     sta ma
        sty mb
        clc
        adc mb
        tax
        bcs .big
        lda sqlo,x
        sta mlo
        lda sqhi,x
        sta mhi
        jmp .diff
.big    lda sqlo2,x
        sta mlo
        lda sqhi2,x
        sta mhi
.diff   lda ma
        sec
        sbc mb
        bcs +
        eor #$ff
        adc #1
+       tax
        lda mlo
        sec
        sbc sqlo,x
        sta mlo
        lda mhi
        sbc sqhi,x
        sta mhi
        rts

; =============================================================================================
;  the starfield: points streaming out from the badge's centre, plotted into the bitmap
; =============================================================================================
rj      jmp .resp                       ; (within branch reach of the star code)
stars   ldx nstar
        dex
        stx si
.sl     ldx si
        lda s_spd,x                     ; d += speed * warp / 16
        ldy warp
        jsr mul
        lda mhi
        sta t1
        lda mlo
        lsr t1
        ror
        lsr t1
        ror
        lsr t1
        ror
        lsr t1
        ror
        ldx si
        clc
        adc st_dlo,x
        sta st_dlo,x
        lda st_dhi,x
        adc t1
        sta st_dhi,x
        bcs rj
        tay
        lda rtab,y                      ; distance from the centre grows with d squared
        cmp #$ff
        beq rj
        sta r
        ldy st_ang,x                    ; x = 160 +- cos * r
        lda cmag,y
        ldy r
        jsr mul
        lda mlo
        asl
        lda mhi
        rol
        sta t1
        ldx si
        ldy st_ang,x
        lda csgn,y
        bne .xneg
        lda #160
        clc
        adc t1
        sta xs
        lda #0
        adc #0
        sta xs+1
        beq .xin
        lda xs
        cmp #64
        bcs rj
        jmp .xin
rj2     jmp .resp
.xneg   lda #160
        sec
        sbc t1
        sta xs
        bcc rj2
        lda #0
        sta xs+1
.xin    ldx si                          ; y = CY +- sin * r * 0.75
        ldy st_ang,x
        lda smag,y
        ldy r
        jsr mul
        lda mlo
        asl
        lda mhi
        rol
        sta t1
        ldx si
        ldy st_ang,x
        lda ssgn,y
        bne .yneg
        lda #CY
        clc
        adc t1
        bcs rj2
        cmp #200
        bcs rj2
        sta ys
        jmp .yin
.yneg   lda #CY
        sec
        sbc t1
        bcc rj2
        sta ys
.yin    jsr erase
        lda ys                          ; cell = row * 40 + column
        lsr
        lsr
        lsr
        tay
        lda xs+1
        lsr
        lda xs
        ror
        lsr
        lsr
        clc
        adc row40lo,y
        sta cell
        lda row40hi,y
        adc #0
        sta cell+1
        lda logo_on                     ; after the landing, keep off the badge and the text
        beq .plot
        lda cell
        clc
        adc #<mask
        sta ptr2
        lda cell+1
        adc #>mask
        sta ptr2+1
        ldy #0
        lda (ptr2),y
        bne .next
.plot   ldy ys                          ; bitmap byte = base + row offset + (x & $1f8)
        lda xs
        and #$f8
        clc
        adc bmplo,y
        sta ptr
        lda bmphi,y
        adc xs+1
        clc
        adc bmbase
        sta ptr+1
        lda xs
        lsr
        and #3
        tay
        lda mcbits,y
        ldx si
        sta st_oldm,x
        ldy #0
        ora (ptr),y
        sta (ptr),y
        lda ptr
        sta st_oldl,x
        lda ptr+1
        sta st_oldh,x
        lda logo_on                     ; colour: colour RAM, except in the hires credit rows
        beq +
        lda ys
        cmp #SPLITY
        bcs .next
+       lda st_dhi,x
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc s_bri,x
        tay
        lda f
        clc
        adc s_ph,x
        and #$1c
        beq +
        lda lumtab,y
        jmp ++
+       lda lumdim,y
++      tax
        lda cell
        sta ptr
        lda cell+1
        clc
        adc #>COLRAM
        sta ptr+1
        txa
        ldy #0
        sta (ptr),y
.next   dec si
        bmi +
        jmp .sl
+       rts
.resp   ldx si                          ; off the screen: start again near the middle
        jsr erase
        ldy rndi
        lda rnd,y
        and #63
        sta st_ang,x
        iny
        lda rnd,y
        and #31
        ora #8
        ldx logo_on                     ; after the landing: start just outside the badge
        beq +
        clc
        adc #120
+       ldx si
        sta st_dhi,x
        iny
        sty rndi
        lda #0
        sta st_dlo,x
        jmp .next

erase   ldx si                          ; take the star's last dot away
        lda st_oldh,x
        beq +
        sta ptr+1
        lda st_oldl,x
        sta ptr
        lda st_oldm,x
        eor #$ff
        ldy #0
        and (ptr),y
        sta (ptr),y
        lda #0
        sta st_oldh,x
+       rts

mcbits  !byte $c0,$30,$0c,$03
sparkang !byte 3,13,24,35,45,56
lumtab  !byte 11,12,15,1,1,1,1,1,1
lumdim  !byte 0,11,12,15,15,15,15,15,15

; =============================================================================================
;  the coin: sprite frames chosen per video frame, copied into the free buffer
; =============================================================================================
coin    lda f
        cmp #APPEAR
        bcs +
        lda #0
        sta sh_en
        rts
+       sec
        sbc #APPEAR
        sta idx
        tax
        lda sch_fid,x
        cmp lastfid
        beq .place
        sta lastfid
        tax
        lda coin_n,x
        sta cnt
        lda coin_src_lo,x
        sta ptr
        lda coin_src_hi,x
        sta ptr+1
        lda buf                         ; fill the buffer that isn't on screen
        eor #1
        sta buf
        beq +
        lda #<SPRB
        sta ptr2
        lda #>SPRB
        sta ptr2+1
        jmp .cp
+       lda #<SPRA
        sta ptr2
        lda #>SPRA
        sta ptr2+1
.cp     ldy #63
-       lda (ptr),y
        sta (ptr2),y
        dey
        bpl -
        lda ptr
        clc
        adc #64
        sta ptr
        bcc +
        inc ptr+1
+       lda ptr2
        clc
        adc #64
        sta ptr2
        bcc +
        inc ptr2+1
+       dec cnt
        bne .cp
.place  ldx lastfid
        lda coin_n,x
        sta cnt
        lda coin_nx,x
        sta nx
        lda coin_exp,x
        sta sh_xe
        sta sh_ye
        lda coin_dx,x
        sta dxx
        lda coin_dy,x
        sta dyy
        lda coin_xlo,x
        sta cx
        lda coin_xhi,x
        sta cx+1
        ldx idx
        lda sch_y,x
        sta cy
        lda sch_back,x                  ; the back is darker
        beq +
        lda #15
        sta col
        lda #6
        sta sh_mc1
        jmp ++
+       lda #1
        sta col
        lda #14
        sta sh_mc1
++      lda #6
        sta sh_mc0
        lda buf
        beq +
        lda #22
        jmp ++
+       lda #16
++      sta pbase
        lda #0
        sta msb
        sta k
        lda cx
        sta xs
        lda cx+1
        sta xs+1
        ldx #0
.pl     lda xs
        sta sh_x,x
        lda xs+1
        beq +
        lda bits,x
        ora msb
        sta msb
+       lda cy
        sta sh_y,x
        txa
        clc
        adc pbase
        sta sh_ptr,x
        lda col
        sta sh_col,x
        inc k
        lda k
        cmp nx
        bne +
        lda #0                          ; next row of sprites
        sta k
        lda cx
        sta xs
        lda cx+1
        sta xs+1
        lda cy
        clc
        adc dyy
        sta cy
        jmp ++
+       lda xs
        clc
        adc dxx
        sta xs
        bcc ++
        inc xs+1
++      inx
        cpx cnt
        bne .pl
        lda msb
        sta sh_msb
        ldx cnt
        lda entab,x
        sta sh_en
        lda #$ff
        sta sh_mc
        rts

bits    !byte 1,2,4,8,16,32,64,128
entab   !byte 0,1,3,7,15,31,63,127,255

; =============================================================================================
;  the landing: screen white; under cover, colour RAM for the FLI badge, the credit text, bank 3
; =============================================================================================
land    lda #0
        sta sh_en
        lda #$2b                        ; blank, white
        sta sh_d011
        lda #1
        sta sh_bord
        sta sh_bg
        sta dirty
-       lda dirty                       ; wait until that is on screen
        bne -
        ldx #0                          ; the badge's colour RAM (rows 0-21: 880 bytes)
-       lda fli_col,x
        sta COLRAM,x
        lda fli_col+$100,x
        sta COLRAM+$100,x
        lda fli_col+$200,x
        sta COLRAM+$200,x
        inx
        bne -
        ldx #FLI_LINES/8*40-$300-1
-       lda fli_col+$300,x
        sta COLRAM+$300,x
        dex
        cpx #$ff
        bne -
        ldx #NST-1                      ; the stars start afresh in bank 3, fewer of them
        lda #0
-       sta st_oldh,x
        dex
        bpl -
        ldx #5                          ; six of them fly off the rim as sparks
-       lda sparkang,x
        sta st_ang,x
        lda #124
        sta st_dhi,x
        lda #0
        sta st_dlo,x
        dex
        bpl -
        lda #6
        sta nstar
        lda #>BMP3
        sta bmbase
        lda #0
        sta sh_bank
        lda #1
        sta logo_on
        sta landed
        rts

; ---- the credit lines, drawn from the C64's own character set ------------------------------
text    lda #<LINE1_BMP                 ; line 1: normal size, half a character right
        sta dst
        lda #>LINE1_BMP
        sta dst+1
        lda #0
        sta k
.t1     ldx k
        lda line1_txt,x
        jsr glyph
        ldy #0
-       lda (gl),y
        lsr
        lsr
        lsr
        lsr
        ora (dst),y
        sta (dst),y
        lda (gl),y
        asl
        asl
        asl
        asl
        sta t1
        tya
        clc
        adc #8
        tay
        lda t1
        ora (dst),y
        sta (dst),y
        tya
        sec
        sbc #7
        tay
        cpy #8
        bne -
        lda dst
        clc
        adc #8
        sta dst
        bcc +
        inc dst+1
+       inc k
        lda k
        cmp #NLINE1
        bne .t1
        lda #<TITLE_BMP                 ; line 2: double size (each dot 2 x 2)
        sta dst
        lda #>TITLE_BMP
        sta dst+1
        lda #0
        sta k
.t2     ldx k
        lda title_txt,x
        jsr glyph
        ldy #0
.tr     sty t2
        lda (gl),y
        sta t1
        tya
        and #3
        asl
        sta r                           ; dot row inside the cell: 0,2,4,6
        lda dst
        sta ptr
        lda dst+1
        sta ptr+1
        cpy #4                          ; glyph rows 4-7 go to the next character row
        bcc +
        lda ptr
        clc
        adc #<320
        sta ptr
        lda ptr+1
        adc #>320
        sta ptr+1
+       lda t1
        lsr
        lsr
        lsr
        lsr
        tax
        lda dbl,x
        ldy r
        sta (ptr),y
        iny
        sta (ptr),y
        lda t1
        and #$0f
        tax
        lda dbl,x
        pha
        lda r
        clc
        adc #8
        tay
        pla
        sta (ptr),y
        iny
        sta (ptr),y
        ldy t2
        iny
        cpy #8
        bne .tr
        lda dst
        clc
        adc #16
        sta dst
        bcc +
        inc dst+1
+       inc k
        lda k
        cmp #NTITLE
        bne .t2
        rts

glyph   sta gl                          ; screen code -> FONT + code * 8
        lda #0
        sta gl+1
        asl gl
        rol gl+1
        asl gl
        rol gl+1
        asl gl
        rol gl+1
        lda gl+1
        clc
        adc #>FONT
        sta gl+1
        rts

dbl     !byte $00,$03,$0c,$0f,$30,$33,$3c,$3f,$c0,$c3,$cc,$cf,$f0,$f3,$fc,$ff

; =============================================================================================
;  after the landing: flash and jolt, sprite script, twinkles, flames, credits, switch-off
; =============================================================================================
post    lda f                           ; idx = f - FACE (capped at 255)
        sec
        sbc #FACE
        sta idx
        lda f+1
        sbc #0
        beq +
        lda #255
        sta idx
+       lda idx
        cmp #LANDON
        bcc +
        lda #1                          ; the white blank is over: FLI on
        sta fli_on
+       lda idx
        cmp #FLASHLEN
        bcs +
        tax
        lda fl_d011,x
        sta sh_d011
        lda fl_xs,x
        sta sh_xs
        lda fl_col,x
        sta sh_bord
        sta sh_bg
        lda #$18
        sta d016b
        jmp ++
+       lda #$08
        sta d016b
        lda #$3b
        sta sh_d011
        lda #0
        sta sh_xs
        sta sh_bord
        sta sh_bg
++      lda #0                          ; sprites from the script
        sta sh_mc
        lda idx
        cmp #TRL
        bcc +
        lda #0
        sta sh_en
        jmp .fx
+       tay
        !for s, 0, 7 {
        lda tr_ptr + s*TRL, y
        sta sh_ptr + s
        lda tr_y + s*TRL, y
        sta sh_y + s
        lda tr_col + s*TRL, y
        sta sh_col + s
        lda tr_x + s*TRL, y
        asl
        sta sh_x + s
        ror msb
        }
        lda msb
        sta sh_msb
        lda tr_en,y
        sta sh_en
        lda tr_xe,y
        sta sh_xe
        lda tr_ye,y
        sta sh_ye
!if CAL {
        lda #$c0                        ; sprite 6: 42 lines from FLI line 40; sprite 7: 21 lines from 70
        sta sh_en
        sta sh_xe
        lda #$40
        sta sh_ye
        lda #90
        sta sh_y+6
        lda #120
        sta sh_y+7
        lda #200
        sta sh_x+6
        lda #250
        sta sh_x+7
        lda #0
        sta sh_msb
        lda #94
        sta sh_ptr+6
        lda #78
        sta sh_ptr+7
        lda #1
        sta sh_col+6
        sta sh_col+7
}

.fx     lda f+1                         ; switch-off time?
        cmp #>OUT
        bcc .live
        bne +
        lda f
        cmp #<OUT
        bcc .live
+       jmp tvoff

.live   lda f+1                         ; light show running?
        bne +
        lda f
        cmp #FX
        bcc .credit
+       lda f
        lsr
        bcs .flames
        ldx #NTWK-1                     ; ring stars twinkle (even frames)
-       lda twk_lo,x
        sta ptr
        lda twk_hi,x
        sta ptr+1
        lda f
        clc
        adc twk_ph,x
        lsr
        and #31
        tay
        lda twkcol,y
        ldy #0
        sta (ptr),y
        dex
        bpl -
        jmp .credit
.flames ldx #NFLAME-1                   ; engine flames flicker (odd frames)
-       lda flm_lo,x
        sta ptr
        lda flm_hi,x
        sta ptr+1
        txa
        asl
        asl
        asl
        adc f
        tay
        lda rnd,y
        and #7
        tay
        lda flmcol,y
        ldy #0
        sta (ptr),y
        dex
        bpl -

.credit lda f                           ; line 1 fades in at CREDIT
        sec
        sbc #<CREDIT
        tax
        lda f+1
        sbc #>CREDIT
        bcc .cdone
        lda drawn                       ; draw the text the first time (hidden: colour 0)
        bne +
        inc drawn
        jsr text
        rts
+       lda f
        sec
        sbc #<CREDIT
        tax
        lda f+1
        sbc #>CREDIT
        beq +
        ldx #255
+       txa
        lsr
        lsr
        lsr
        cmp #3
        bcc +
        lda #3
+       tax
        lda c1fade,x
        jsr line1c
        lda f                           ; line 2 at NAME
        sec
        sbc #<NAME
        tax
        lda f+1
        sbc #>NAME
        bcc .cdone
        beq +
        ldx #255
+       txa
        lsr
        lsr
        lsr
        cmp #3
        bcc +
        lda #3
+       tax
        lda c2fade,x
        jsr line2c
.cdone  rts

line1c  cmp lastc1                      ; colour the line-1 cells (only when it changes)
        beq +
        sta lastc1
        ldx #NLINE1C-1
-       ldy line1_cells,x
        sty ptr
        ldy line1_cellh,x
        sty ptr+1
        ldy #0
        sta (ptr),y
        dex
        bpl -
+       rts

line2c  cmp lastc2
        beq +
        sta lastc2
        ldx #NTITLEC-1
-       ldy title_cells,x
        sty ptr
        ldy title_cellh,x
        sty ptr+1
        ldy #0
        sta (ptr),y
        dex
        bpl -
+       rts

; ---- the old-TV switch-off: lines go black from the top and bottom towards the middle -----
tvoff   lda outclr                      ; first time: the hires stars go dark
        bne +
        inc outclr
        lda #0
        ldx #3*40-1
-       sta FLI+FLI_LINES/8*40,x
        dex
        bpl -
        lda #$ff
        sta lastc1
        sta lastc2
+       lda f                           ; k = frames since OUT
        sec
        sbc #<OUT
        cmp #TVLEN
        bcc +
        lda #TVLEN-1
+       tax
        lsr                             ; credits fade down, one step per 8 frames
        lsr
        lsr
        cmp #4
        bcc +
        lda #4
+       tay
        lda tvh,x
        sta t2
        lda c1out,y
        jsr line1c
        lda c2out,y
        jsr line2c
-       lda curh                        ; close in, two lines at a time
        cmp t2
        beq +
        bcc +
        lda #MID
        sec
        sbc curh
        jsr blank
        lda #MID-1
        clc
        adc curh
        jsr blank
        dec curh
        jmp -
+       rts

blank   tay                             ; line y: set the invalid-mode bit in its $d011 value
        lda op_lo,y
        sta ptr
        lda op_hi,y
        sta ptr+1
        ldy #0
        lda (ptr),y
        ora #$40
        sta (ptr),y
        rts

twkcol  !byte 1,1,1,15,15,12,12,15,15,1,1,1,1,1,1,1, 1,1,15,12,11,12,15,1,1,1,1,1,1,1,1,1
flmcol  !byte 1,3,14,1,15,3,1,13
c1fade  !byte $00,$b0,$c0,$f0
c2fade  !byte $00,$90,$80,$70
c1out   !byte $f0,$c0,$b0,$00,$00
c2out   !byte $70,$80,$90,$00,$00

; =============================================================================================
;  the end: quiet, then a reset back to BASIC
; =============================================================================================
finish  sei
        lda #0
        sta $d01a
        sta $d015
        lda #$ff
        sta $d019
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$0b
        sta $d011
        lda #$37
        sta $01
        jmp $fce2

; =============================================================================================
        !source "build/assets.asm"
main_end
        !if low_end > $8000 { !error "program runs into bank 2 at $8000" }
        !if main_end > $a000 { !error "high data runs into the bank 2 bitmap at $a000" }
