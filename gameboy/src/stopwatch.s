;
; Stopwatch (lag test) for 240p test suite
; Copyright 2018 Damian Yerrick
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program; if not, write to the Free Software Foundation, Inc.,
; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
;
include "src/gb.inc"
include "src/global.inc"

; Stopwatch: Lag test

section "stopwatchchrlo",ROM0
; This is temporarily moved into ROM0 while
; writing the GBC-exclusive tests' help
stopwatchdigits_chr:
  incbin "obj/gb/stopwatchdigits.chrgb.pb16"
sizeof_stopwatchdigits_chr = 1024

section "stopwatchchr",ROMX
stopwatchface_chr:
  incbin "obj/gb/stopwatchface.u.chrgb.pb16"
sizeof_stopwatchface_chr = 1296
stopwatchface_nam:
  incbin "obj/gb/stopwatchface.nam"

stopwatchhand_chr:
  incbin "obj/gb/stopwatchhand.chrgb.pb16"
sizeof_stopwatchhand_chr = 1536

; X, Y coordinates of 1,1
sw_hand_xy:
  db  76, 58
  db  98, 65
  db 112, 84
  db 112,108
  db  98,127
  db  76,134
  db  54,127
  db  40,108
  db  40, 84
  db  54, 65


  rsset hTestState
hours       rb 1
minutes_bcd rb 1
seconds_bcd rb 1
frames_bcd  rb 1
is_running  rb 1

; "Lap" pauses blitting (instead "LAP" is shown) but continues running
is_lap      rb 1
is_ruler    rb 1
hide_face   rb 1

section "stopwatch",ROM0
activity_stopwatch::
  xor a
  ldh [is_running],a
  ldh [is_lap],a
  ldh [is_ruler],a
  ldh [hours],a
  ldh [frames_bcd],a
  ldh [minutes_bcd],a
  ldh [seconds_bcd],a
  ldh [hide_face],a
.restart:
  call clear_gbc_attr

  ; Load background tiles
  ld a,bank(stopwatchface_chr)
  ld [rMBC1BANK1],a
  ld de,stopwatchface_chr
  ld hl,CHRRAM2
  ld b,sizeof_stopwatchface_chr/16
  call pb16_unpack_block

  ; Load background tilemap
  ld h,0
  ld de,_SCRN0
  ld bc,32*18
  call memset
  ld de,_SCRN1
  ld bc,32*18
  call memset
  ld hl,stopwatchface_nam
  ld de,_SCRN0+5*32+4
  ld bc,12*256+13
  call load_nam

  ; Load other tiles used by activity
  ld de,stopwatchdigits_chr
  ld hl,CHRRAM1
  ld b,sizeof_stopwatchdigits_chr/16
  call pb16_unpack_block
  ld de,stopwatchhand_chr
  ld hl,CHRRAM0
  ld b,sizeof_stopwatchhand_chr/16
  call pb16_unpack_block

  ; Legend in $F0-$FF
  call vwfClearBuf
  ld hl,digits_label_msg
  .legendloop:
    ld a,[hl+]
    ld b,a
    call vwfPuts
    ld a,[hl+]
    or a
    jr nz,.legendloop
  ld hl,CHRRAM1+$0700
  ld b,$FF
  call vwfPutBuf03

  ld a,$F0
  ld hl,_SCRN0+2
  ld [hl+],a
  inc a
  ld [hl+],a
  inc a
  inc l
  .legendtileloop:
    ld [hl+],a
    inc a
    jr nz,.legendtileloop

  call sw_convert
  call sw_blit
  call sw_init_oam
  call run_dma

  ; Turn on rendering
  ld a,%11100100
  call set_bgp
  call set_obp0
  ld a,7
  ldh [rWX],a
  ld a,40      ; BG below inactive circles can be toggled by showing
  ldh [rWY],a   ; or hiding window
  ld a,255
  ldh [rLYC],a  ; rSTAT rLYC not used by this activity
  ld a,LCDCF_ON|BG_NT0|BG_CHR21|OBJ_ON|WINDOW_NT1
  ld [vblank_lcdc_value],a
  ldh [rLCDC],a

.loop:
  ld b,helpsect_stopwatch
  call read_pad_help_check
  jp nz,.restart

  ; Process input
  ld a,[new_keys]
  ld b,a
  bit PADB_B,a
  ret nz
  
  ; A: Start/stop
  bit PADB_A,b
  jr z,.not_start_stop
    ldh a,[is_running]
    xor 1
    ldh [is_running],a
  .not_start_stop:
  
  ; TODO: Select: Lap/reset (the most complicated among these)
  bit PADB_SELECT,b
  jr z,.not_lap_reset
    ; Select while in lap: Clear lap
    ldh a,[is_lap]
    or a
    jr z,.not_already_lap
    xor a
    jr .have_lap
  .not_already_lap:
    ; Select while not in lap and while running: Enable lap
    ldh a,[is_running]
    or a
    jr nz,.have_lap

    ; Select while not in lap and not running: Clear to 0
    ld [frames_bcd],a
    ld [seconds_bcd],a
    ld [minutes_bcd],a
    ld [hours],a
    
  .have_lap:
  ldh [is_lap],a
  .not_lap_reset:

  ; Up: Toggle ruler
  bit PADB_UP,b
  jr z,.not_toggle_ruler
    ldh a,[is_ruler]
    xor 1
    ldh [is_ruler],a
  .not_toggle_ruler:
  
  ; Down: Toggle visibility of BG below rLYC
  bit PADB_DOWN,b
  jr z,.not_toggle_face
    ld a,[hide_face]
    xor $01  ; BG enable
    ld [hide_face],a
  .not_toggle_face:

  ; Increment the counter by one frame
  ldh a,[is_running]
  or a
  jr z,.not_running
    ldh a,[frames_bcd]
    inc a
    daa
    cp $60
    jr c,.not_wrap_frames
      xor a
    .not_wrap_frames:
    ldh [frames_bcd],a
    jr c,.not_running

    ldh a,[seconds_bcd]
    inc a
    daa
    cp $60
    jr c,.not_wrap_seconds
      xor a
    .not_wrap_seconds:
    ldh [seconds_bcd],a
    jr c,.not_running

    ldh a,[minutes_bcd]
    inc a
    daa
    cp $60
    jr c,.not_wrap_minutes
      xor a
    .not_wrap_minutes:
    ldh [minutes_bcd],a
    jr c,.not_running
  .not_running:

  ldh a,[is_lap]
  or a
  jr nz,.skipping_convert_for_lap
    call sw_convert
    call sw_draw_clock_hand
  .skipping_convert_for_lap:
  call sw_draw_ruler

  call wait_vblank_irq
  call run_dma
  call sw_blit

  ; Show or hide the 
  ld a,[hide_face]
  rra    ; 1: Hide face; 0: Show
  ccf    ; 0: Hide face; 1: Show
  sbc a  ; $00: Hide face; $FF: Show
  or 40  ; $28: Hide face; $FF: Show
  ldh [rWY],a
  jp .loop

digits_label_msg:
  db 4,"hr",10
  db 19,"minute",10
  db 58,"second",10
  db 100,"frame",0

; Drawing the digits ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  
sw_convert:
  ld hl,help_line_buffer
  ldh a,[hours]
  call .convert_1digit
  ldh a,[minutes_bcd]
  call .convert_2digits
  ldh a,[seconds_bcd]
  call .convert_2digits
  ldh a,[frames_bcd]
.convert_2digits:
  push af
  swap a
  and $0F
  call .convert_1digit
  pop af
  and $0F
.convert_1digit:
  add a
  ld c,a
  add c
  add c
  add $80
  ld [hl+],a
  ret

;;
; Write the converted digits at (1,2)
sw_blit:
  ; B: amount to add (0, 2, 4); C: colon tile ($00 or $BC)
  ld bc,$0000
  ld hl,_SCRN0+32*1+2
.rowloop:
  ld de,help_line_buffer
  ld a,[de]  ; hours digit: $80 + 6 * hours
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,c     ; colon tile
  ld [hl+],a

  ld a,[de]  ; tens of minutes digit
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,[de]  ; minutes digit
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,c     ; colon tile
  ld [hl+],a

  ld a,[de]  ; tens of seconds digit
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,[de]  ; seconds digit
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,c     ; colon tile
  ld [hl+],a

  ld a,[de]  ; tens of frames digit
  inc de
  add b
  ld [hl+],a
  inc a
  ld [hl+],a
  ld a,[de]  ; frames digit
  add b
  ld [hl+],a
  inc a
  ld [hl],a
  ld a,16    ; Move to next line
  add l
  ld l,a

  ld c,$BC   ; second and third rows of colon use dot tile
  inc b
  inc b
  ld a,b
  cp 6
  jr c,.rowloop

  ; Draw lap indicator
  ld hl,_SCRN0+32*4+17
  ldh a,[is_lap]
  or a
  jr z,.nolap1
  ld a,$BE
.nolap1:
  ld [hl+],a
  jr z,.nolap2
  inc a
.nolap2:
  ld [hl+],a
  ret

; Drawing the hand (the sprites on the face at bottom half) ;;;;;;;;;

; Static allocation of OAM:
; 0-8 face digit
; 9 dot
; 10-27 left column
; 28-39 unused

sw_init_oam:

  ; Set X, tile, and attribute of sprites that make up ruler
  ld hl,SOAM+10*4
  ld b,18
  .rulerobjloop:
    inc hl  ; Skip Y
    ld a,b
    rra
    ld a,8
    jr nc,.notrulerR
      ld a,14
    .notrulerR:
    ld [hl+],a  ; 1. X
    ld a,$BD
    ld [hl+],a  ; 2. tile
    xor a
    ld [hl+],a  ; 3. black
    dec b
    jr nz,.rulerobjloop
  ; Fall through to sw_draw_ruler

sw_draw_ruler:
  ld hl,SOAM+10*4
  ; TODO: Draw Y coordinates of ruler sprites if ruler enabled
  ldh a,[is_ruler]
  or a
  jr z,.no_ruler
  ld a,16
  .rulerloop:
    ld [hl+],a
    add 8
    inc l
    inc l
    inc l
    cp 160
    jr c,.rulerloop
  .no_ruler:

  ld a,l
  ld [oam_used],a
  jp lcd_clear_oam

sw_draw_clock_hand:
  ldh a,[frames_bcd]
  and $0F
  ld b,a
  add a
  add b  ; A=3
  cp 15
  jr c,.not5to9
    add 48-15
  .not5to9:
  ldh [Lspriterect_tile],a
  
  ; Look up XY coord
  ld a,b
  ld de,sw_hand_xy
  call de_index_a
  ld a,l
  ldh [Lspriterect_x],a
  ld a,h
  ldh [Lspriterect_y],a

  ; Draw the small dot halfway out
  ld hl,SOAM
  add 112  ; Y center position
  rra
  ld [hl+],a
  ldh a,[Lspriterect_x]
  add 92  ; X center position
  rra
  ld [hl+],a
  ld a,$0F  ; dot tile
  ld [hl+],a
  xor a     ; attr 0
  ld [hl+],a
  ld a,l
  ld [oam_used],a

  ; Draw the large dot with a number on it
  xor a
  ldh [Lspriterect_attr],a
  ld a,3
  ldh [Lspriterect_height],a
  ldh [Lspriterect_width],a
  ld a,16
  ldh [Lspriterect_tilestride],a
  ld a,8
  ldh [Lspriterect_rowht],a
  jp draw_spriterect

