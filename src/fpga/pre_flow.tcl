# Quartus pre-flow script (runs in the project directory).
# C64_MiSTer's ROM images are named relative to its own project directory
# (rtl/roms/..., rtl/iec_drive/...);
# copy them to where those paths point from this project.
file mkdir rtl/roms rtl/iec_drive
foreach f [glob C64_MiSTer/rtl/roms/*.mif] { file copy -force $f rtl/roms/ }
foreach f [glob C64_MiSTer/rtl/iec_drive/*.mif] { file copy -force $f rtl/iec_drive/ }

source apf/build_id_gen.tcl
