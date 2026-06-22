"""
Milometry App Store / Google Play Screenshot Processor
------------------------------------------------------
1. Crops the phone status bar from the top (proportional, resolution-independent)
2. Fits each shot onto the exact store canvas WITHOUT cropping content (pads with a
   clean background color so titles and bottom buttons are never cut off)
3. Writes one subfolder per required size into 'output/'

HOW TO USE:
1. Put your raw phone screenshots (.png/.jpg/.jpeg) into the 'Screenshots' folder
2. Run:  python process_screenshots.py
3. Find processed images in 'output/<size>/'
"""

from PIL import Image
import os

# --- Settings ---
INPUT_FOLDER = "Screenshots"
OUTPUT_FOLDER = "output"
STATUS_BAR_FRACTION = 0.038   # crop top ~3.8% of height (the phone status bar)
PAD_COLOR = (255, 255, 255)   # white padding behind the fitted screenshot

# Target sizes: (label, width, height)
SIZES = [
    ("6.9inch", 1320, 2868),       # iPhone 6.9" (16 Pro Max) — current App Store slot
    ("6.7inch", 1290, 2796),       # iPhone 6.7" (also accepted in the 6.9" slot)
    ("6.5inch", 1242, 2688),       # iPhone 6.5" (XS Max / 11 Pro Max)
    ("13inch_iPad", 2048, 2732),   # 13-inch iPad Pro
    ("google_play", 1080, 2400),   # Google Play phone (ratio within 1:2..2:1)
]
# ----------------

os.makedirs(OUTPUT_FOLDER, exist_ok=True)

supported = (".png", ".jpg", ".jpeg")
files = sorted([f for f in os.listdir(INPUT_FOLDER) if f.lower().endswith(supported)])

if not files:
    print(f"No images found in '{INPUT_FOLDER}' folder.")
else:
    print(f"Found {len(files)} screenshot(s).")
    for size_label, TARGET_W, TARGET_H in SIZES:
        size_folder = os.path.join(OUTPUT_FOLDER, size_label)
        os.makedirs(size_folder, exist_ok=True)
        print(f"\n--- {size_label} ({TARGET_W}x{TARGET_H}) ---")

        for i, filename in enumerate(files, 1):
            img = Image.open(os.path.join(INPUT_FOLDER, filename)).convert("RGB")
            w, h = img.size

            # Step 1: crop the status bar from the top
            crop_top = int(h * STATUS_BAR_FRACTION)
            img = img.crop((0, crop_top, w, h))
            w, h = img.size

            # Step 2: scale to FIT inside the canvas (contain — never crop content)
            scale = min(TARGET_W / w, TARGET_H / h)
            new_w, new_h = int(round(w * scale)), int(round(h * scale))
            fitted = img.resize((new_w, new_h), Image.LANCZOS)

            # Step 3: paste centered onto an exact-size padded canvas
            canvas = Image.new("RGB", (TARGET_W, TARGET_H), PAD_COLOR)
            canvas.paste(fitted, ((TARGET_W - new_w) // 2, (TARGET_H - new_h) // 2))

            out_name = f"screenshot_{i:02d}.png"
            canvas.save(os.path.join(size_folder, out_name), "PNG")
            print(f"  ok  {filename} -> {out_name}")

    print(f"\nDone. Processed images are in '{OUTPUT_FOLDER}/<size>/'.")
