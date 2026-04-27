import os
import sys

wm_path = os.path.join(os.path.dirname(__file__), "wm.asm")
out_path = os.path.join(os.path.dirname(__file__), "wm_taskbar.asm")

with open(wm_path, "r", encoding="utf-8") as f:
    lines = f.read().split("\n")

wm_str_len_to_btns = lines[275:365]  
sm_constants_to_draw = lines[366:454]
sm_hide = lines[508:515]             
taskbar_clock = lines[2304:2409]     

out = []
out.append("; ===========================================================================")
out.append("; pm/gui/wm_taskbar.asm  -  Taskbar and Start Menu Rendering")
out.append("; ===========================================================================")
out.append("")
out.append("[BITS 32]")
out.append("")
out.extend(wm_str_len_to_btns)
out.append("")
out.extend(taskbar_clock)
out.append("")
out.extend(sm_constants_to_draw)
out.append("")
out.extend(sm_hide)

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))

# Delete in reverse order to not invalidate array boundaries
del lines[2304:2409]
del lines[508:515]
del lines[366:454]
del lines[275:365]

with open(wm_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("Extraction successful!")
