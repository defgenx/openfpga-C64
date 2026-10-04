# Installing the Commodore 64 core on the Analogue Pocket

## 1. Copy the core to the microSD card

**The easy way:** put the microSD card in your computer and run the installer, from a clone of the repo
or on its own after downloading it from the release page:

| System        | Run                                                                 |
|---------------|---------------------------------------------------------------------|
| Windows       | double-click **`install.bat`** (or `.\install.ps1` in PowerShell)  |
| macOS / Linux | `./install.sh`                                                      |

It finds the Pocket SD card, asks you to confirm, copies the core and this guide, and offers to eject the
card. Options: `--dry-run` / `-DryRun` shows what would be copied and changes nothing;
`--sd /Volumes/POCKET` / `-SD E:\` names the card yourself.

**It never replaces a file without asking.** Files already on the card that are identical are skipped.
For each one that differs it asks `Replace it? [y]es / [N]o / [a]ll / [s]kip all`; pressing Enter keeps
the card's file. Run without a console (or with the dry-run option), it never replaces anything and lists
what differs. Without a built core next to it, the installer downloads the newest release from GitHub.

**By hand:** copy the contents of `defgenx.C64.zip` (or the `release/` folder made by `./build.sh`) to
the **root** of the card, merging with the folders already there:

```
SD card root
├── Assets/
│   └── c64/
│       └── common/              <- your .prg .crt .d64 .g64 .d81 .tap files go here
├── Cores/
│   └── defgenx.C64/
│       ├── c64.rbf_r            <- the core bitstream
│       ├── core.json  data.json  input.json  interact.json  video.json ...
└── Platforms/
    └── c64.json
```

On macOS, copy the folders with Finder or `ditto`. Don't replace the existing `Assets`, `Cores` or
`Platforms` folders; merge into them. Eject the card cleanly afterwards.

## 2. ROMs (nothing to do)

The C64's BASIC, KERNAL and character ROMs and the 1541 / 1581 ROMs are built into the core, as on MiSTer,
so it boots to BASIC with no other file.

To use another kernal (JiffyDOS, DolphinDOS, SpeedDOS), make a System ROM file as for MiSTer — BASIC,
then KERNAL, then the 1541 ROM, concatenated (32 KB, or 48 KB with a 32 KB 1541 ROM) — put it in
`Assets/c64/common/` and pick it in *Core Settings → System ROM*. The C64 resets with it, and it is loaded
again at every start. DolphinDOS and SpeedDOS ROM sets with a 32 KB drive ROM also enable the fast
parallel cable between the C64 and the drives.

## 3. Add software

Copy files to `Assets/c64/common/`, then load them from *Core Settings*:

| File                     | Slot          | Then                                                  |
|--------------------------|---------------|-------------------------------------------------------|
| `.prg`                   | Program       | it starts by itself                                   |
| `.crt`                   | Cartridge     | it starts by itself                                   |
| `.d64` / `.g64` / `.d81` | Disk          | type `LOAD"*",8,1` and Return, then `RUN` and Return   |
| `.tap`                   | Tape          | type `LOAD` and Return; the tape starts by itself      |

The on-screen keyboard (Select) types the commands; `LOAD"*",8,1` needs SHIFT + 2 for `"`. With a disk
inserted, `LOAD"$",8` and `LIST` show its directory.

* Disks are **writable**: what a game saves is written back to the file on the card. Keep backups. Set
  *Write Protect* (before inserting the disk) to keep a disk unchanged.
* `.d64` can't hold copy protection; when a game doesn't load from its `.d64`, look for a `.g64`.
* `.t64` and `.d71` are not supported; convert `.t64` to `.d64` (for example with DirMaster).

## 4. Start it

On the Pocket: *openFPGA → Commodore 64*. The BASIC screen appears in a second.

Useful settings (*Core Settings*):

| Setting       | What it does                                              |
|---------------|-----------------------------------------------------------|
| Video         | PAL (most European games) or NTSC (US games)              |
| Joystick Port | Port 2 (most games) or Port 1                             |
| Pad Mode      | Joystick (default), Keys or Mouse                         |
| Model         | C64 (6581 SID) or C64C (8580 SID)                         |
| Borders       | Show or hide the screen borders                           |
| Reset         | Like switching the C64 off and on, keeping the cartridge  |
| Reset All Settings | Puts every setting back to its default, then a reset |

## Controls

**Start** cycles the pad: **Joystick** (default) → **Keys** → **Mouse** → Joystick. A label shows the
new mode for two seconds.

| Button | Joystick | Keys | Mouse | On-screen keyboard |
|---|---|---|---|---|
| D-pad | joystick | cursor keys | pointer | move cursor |
| A | fire | Space | left button | press key |
| B | Space | Return | right button | close |
| X / Y | Return / F1 | F1 / F3 | Space / Return | – |
| L / R | Run/Stop / F7 | Run/Stop / F5 | Run/Stop / F1 | – |
| **Select** | keyboard | keyboard | keyboard | close |

On the on-screen keyboard CTRL, SHIFT and C= are sticky: press SHIFT, then the key. In the Dock, a USB
keyboard and mouse work too (Esc = Run/Stop, Tab = C=, F11 = Restore).

## Troubleshooting

* **Stuck after changing a setting:** in *Core Settings* choose **Reset All Settings**. If you cannot
  reach the menu, erase the saved settings: `./install.sh --reset-settings` (Windows:
  `install.bat -ResetSettings`), or delete the folder `Settings/defgenx.C64/` on the card.
* **`?DEVICE NOT PRESENT ERROR`:** no disk in drive 8 — pick one in *Disk*.
* **The joystick does nothing:** Start until the label says JOYSTICK; try *Joystick Port = Port 1*.
* **Wrong speed or rolling picture:** the game is for the other video standard — change *Video*.
