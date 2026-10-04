# Input

## Pocket pads

| Button  | Joystick (default)   | Keys        | Mouse            | Keyboard shown      |
|---------|----------------------|-------------|------------------|---------------------|
| D-pad   | joystick             | cursor keys | move the pointer | move the key cursor |
| A       | fire                 | Space       | left button      | press the key       |
| B       | Space                | Return      | right button     | close the keyboard  |
| X       | Return               | F1          | Space            | -                   |
| Y       | F1                   | F3          | Return           | -                   |
| L       | Run/Stop             | Run/Stop    | Run/Stop         | -                   |
| R       | F7                   | F5          | F1               | -                   |
| Select  | show the keyboard    | show the keyboard | show the keyboard | close        |
| Start   | -> keys              | -> mouse    | -> joystick      | -                   |

*Pad Mode* in the core settings picks the starting mode; Start cycles joystick -> keys -> mouse, and a
label shows the new mode for ~2 s. Pad 1 is joystick port 2 unless *Joystick Port* says port 1 (it sets
c64.sv's swap bit); pad 2 is the other port. In mouse mode the D-pad (or a Dock analog stick) drives
C64_MiSTer's 1351 emulation on port 1. Dock pads 3 and 4 are the user port 4-player adapter, as on MiSTer.

## On-screen keyboard

Select opens a 16×5 keyboard at the bottom of the picture (`osk.sv`, 20-pixel cells so it fits the
320-pixel display window). CTRL, SHIFT and C= are sticky: press them once, then the key; they release with
it. Other keys are held for as long as A is held. While the keyboard is shown the joystick is disconnected.

Two-letter labels: `RS` Run/Stop, `RE` Restore, `HM` Clr/Home, `DL` Inst/Del, `IN` Inst, `RT` Return,
`SL` Shift Lock, `CT` CTRL, `SH` Shift, `SP` Space, `<-` and `^` the C64's left-arrow and up-arrow keys.
The layout is `LAYOUT` in `tools/gen_osk.py`, which generates `src/fpga/core/osk_layout.svh` and the font
ROM `osk_font.hex` (font8x8 by Daniel Hepper, public domain, plus arrow and pound glyphs). Re-run it after
editing: `python3 tools/gen_osk.py tools/font8x8_basic.h`.

## Dock keyboard and mouse

The Dock reports a USB keyboard as player 3 and a USB mouse as player 4 (`cont3/4_key[31:28]` = 4 / 5):

* keyboard: `{cont3_joy, cont3_trig}` holds up to six HID usages, `cont3_key[15:8]` the modifier byte;
* mouse: `cont4_key[15:0]` is a report counter, `cont4_joy[15:0]` / `cont4_trig[15:0]` the relative X / Y
  motion (little-endian), `cont4_joy[17:16]` the buttons.

`hid_c64` turns these, and the keys made by the pad and the on-screen keyboard, into the `ps2_key` and
`ps2_mouse` words MiSTer's `hps_io` produces, so C64_MiSTer's `fpga64_keyboard` and `c1351` are used
unchanged:

* Keyboard: the held keys are compared with the keys already reported, one pair per clock; each
  difference is a make or break event (`ps2_key[10]` toggles), at most one per millisecond. HID usages map
  to the PS/2 set 2 codes fpga64_keyboard knows, so the layout is MiSTer's: Esc = Run/Stop, Tab or Alt =
  C=, Backspace = Inst/Del, Home = Clr/Home, F11 = Restore, F9 = ↑, F10 / End = `=`, `` ` `` = ←,
  `[` = @, `]` = *, `\` = £, Page Up = tape play, Caps Lock = Shift Lock.
* Mouse: motion is accumulated and reported at most once per millisecond, ±31 counts per report (the
  1351 adds 6 bits per report).

## Not supported

Paddles; two simultaneous non-modifier keys from the on-screen keyboard.
