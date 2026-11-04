# Video

The APF video clock is clk_sys (31.53 MHz PAL, 32.73 MHz NTSC), the C64's own master clock. The VIC-II
puts out one pixel every 4 clocks; `c64_video` samples it 2 clocks after the `hblank` fall and every 4
clocks after that, and marks the other 3 clocks `video_skip`.

## Fixed windows

`c64_video` cuts a fixed window out of every frame, counted from `video_sync`'s blanking edges (pixels
from the `hblank` fall, lines from the `vblank` fall), so the scaler always sees the same DE geometry.
The standard and the border setting are latched at each `vsync`.

Numbers measured with C64_MiSTer's own `video_vicII_656x` and `video_sync`, simulated with nvc
(`sim/vic/tb_vic.vhd`, a text screen with border and background in different colours):

| Standard        | Active area (blanking off) | 320×200 display window |
|-----------------|----------------------------|------------------------|
| PAL (6569)      | 382 × 270                  | x 32–351, y 34–233     |
| NTSC (6567R8)   | 404 × 250                  | x 43–362, y 25–224     |

| Slot | Mode              | Window           | Size    | Aspect |
|------|-------------------|------------------|---------|--------|
| 0    | PAL, borders      | x 0, y 0         | 384×270 | 4:3    |
| 1    | PAL, no borders   | x 32, y 34       | 320×200 | 3:2    |
| 2    | NTSC, borders     | x 0, y 0         | 404×250 | 40:33  |
| 3    | NTSC, no borders  | x 43, y 25       | 320×200 | 6:5    |

A line is sampled from the `hblank` fall up to the window's end, not up to the `hblank` rise: PAL's
border window is 384 wide, 2 pixels past the 382-pixel active area, so that it has 32 pixels of border on
each side. The VIC still draws the border there (its own blanking starts 7 pixels later). Every scaler
width is a multiple of 4, as in other Pocket cores: the PAL border mode used to be 382 wide, and its
picture was reported broken on hardware while the 404-wide NTSC one was fine.

Aspect ratios come from the pixel clocks (PAL pixels ≈ 0.94:1, NTSC ≈ 0.75:1). The slot is announced on
the first clock with DE low after each line (`video_rgb = {8'h00, slot, 13'h0}`). HS is the `hblank` fall
and VS the `vsync_out` rise, which never share a clock.

`sim/video_tb.sv` replays the VIC-II trace into `c64_video` and checks, for all four modes, the pixels per
line, lines per frame, the slot word, and that the no-border window contains no border pixel while the
border window contains exactly 320×200 display pixels.

## Known gaps

* Aspect ratios are untested on a real screen.
* NTSC always uses the 6567R8 timing (65 cycles, 263 lines), as C64_MiSTer does.
