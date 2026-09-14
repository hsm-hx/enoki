#!/usr/bin/env python3
"""朔と栞の差分素材（idle_1_<v>.png + sprite_1_<v>.png + sprite_2_<v>.png）から
Codex Pet 形式のスプライトセット（8列×9行, 192×208px）を作る。

  python3 scripts/build_variant_atlas.py --src ~/Desktop/codex_pet_skin_sakushio --variant private \
      --reference ~/.codex/pets/sakushio_pet/spritesheet.png \
      --out "$HOME/Library/Application Support/Enoki/Characters/saku_shiori_casual" \
      --id sakushio_casual --name "朔と栞（私服）"

- 各シートは 4 列 × 2 行。列の切れ目はアルファの帯から検出し、検出できない行（横断幕が隣にかかる等）は等分割。
- キャラクターの身長は「基準シート（ベーススキン）の idle_02」に合わせるので、プロファイルを切り替えても
  サイズが変わらない。セルからはみ出す小物（フラッグ等）は端が切れる。
- 描き直しはしない（切り出し・縮小・配置のみ）。
依存: pip install pillow numpy
"""
import argparse, json, sys
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

COLS, ROWS, CW, CH = 8, 9, 192, 208
PAD = 2
TH = 16      # これ以下のアルファは「余白のノイズ」とみなす
GROW = 6     # キャラクターの周りに残す柔らかい縁

# 差分ごとの「シートのセル → コマ名」。ラベルは <シート番号>-<行*4+列>（scripts/ の QA 一覧と同じ）。
MAPPINGS = {
    # 私服（casual）
    "private": {
        "idle_02": "1-0", "idle_03": "1-1", "wave_01": "1-2", "wave_02": "1-3",
        "drag_01": "1-4", "working_01": "1-5", "sleep_01": "1-6", "sleep_02": "1-7",
        "waiting_01": "2-0", "failure_01": "2-1", "review_01": "2-2", "look": "2-3",
        "success_01": "2-4", "waiting_02": "2-5", "working_02": "2-6", "jump": "2-7",
    },
    # レノファ応援（横断幕 1-2 / フラッグ 1-3 を手振りリアクションに使う）
    "renofa": {
        "idle_02": "1-0", "sleep_02": "1-1", "wave_01": "1-2", "wave_02": "1-3",
        "idle_03": "1-4", "working_01": "1-5", "sleep_01": "1-6", "drag_01": "1-7",
        "waiting_01": "2-0", "failure_01": "2-1", "review_01": "2-2", "success_01": "2-3",
        "working_02": "2-4", "look": "2-5", "waiting_02": "2-6", "jump": "2-7",
    },
}

# Codex 固定の 9 行（既存 sakushio_pet と同じ割り当て）
ROW_MAP = [
    ("idle",          ["idle_01", "idle_01", "idle_02", "idle_03", "idle_02", "idle_01"]),
    ("running-right", ["drag_01"] * 8),
    ("running-left",  ["drag_01"] * 8),
    ("waving",        ["waiting_02", "wave_01", "wave_02", "wave_01"]),
    ("jumping",       ["look", "jump", "jump", "success_01", "idle_01"]),
    ("failed",        ["failure_01"] * 5 + ["review_01"] * 3),
    ("waiting",       ["waiting_01", "waiting_01", "waiting_02", "waiting_02", "sleep_01", "sleep_02"]),
    ("running",       ["working_01", "working_02"] * 3),
    ("review",        ["review_01"] * 4 + ["working_01"] * 2),
]


def bands(proj, minw=30):
    out, s = [], None
    for i, v in enumerate(proj):
        if v and s is None:
            s = i
        if not v and s is not None:
            if i - s >= minw:
                out.append((s, i))
            s = None
    if s is not None:
        out.append((s, len(proj)))
    return out


def alpha_bbox(im):
    m = np.asarray(im)[..., 3] > TH
    ys, xs = np.where(m)
    if len(xs) == 0:
        return None
    return (max(xs.min() - GROW, 0), max(ys.min() - GROW, 0),
            min(xs.max() + 1 + GROW, im.width), min(ys.max() + 1 + GROW, im.height))


def slice_sheet(path):
    """4×2 のシートを 8 セルに切る。戻り値: [(image, anchor_x, floor_y)]（セル内ピクセル）"""
    sheet = Image.open(path).convert("RGBA")
    m = np.asarray(sheet)[..., 3] > TH
    yb = bands(m.sum(1) > 2)
    assert len(yb) == 2, f"{path.name}: 行が 2 つ検出できません {yb}"
    ycut = [0, (yb[0][1] + yb[1][0]) // 2, sheet.height]
    cells = []
    for r in range(2):
        xb = bands(m[ycut[r]:ycut[r + 1]].sum(0) > 2)
        if len(xb) == 4:
            xcut = [0] + [(xb[i][1] + xb[i + 1][0]) // 2 for i in range(3)] + [sheet.width]
        else:
            xcut = [round(sheet.width * i / 4) for i in range(5)]
            print(f"  {path.name} 行{r}: 列の帯が {len(xb)} 個なので等分割にします")
        for c in range(4):
            cell = sheet.crop((xcut[c], ycut[r], xcut[c + 1], ycut[r + 1]))
            bb = alpha_bbox(cell)
            if len(xb) == 4:
                ax = (xb[c][0] + xb[c][1]) / 2 - xcut[c]
            else:
                ax = (bb[0] + bb[2]) / 2
            cells.append((cell, ax, bb[3] - GROW))
    return cells


def find_source(src, stem, variant):
    for name in (f"{stem}_{variant}.png", f"{stem}_{variant}", f"{stem}{variant}.png"):
        p = src / name
        if p.exists():
            return p
    raise FileNotFoundError(f"{src}/{stem}_{variant}.png が見つかりません")


def content_height(im):
    bb = alpha_bbox(im)
    return bb[3] - bb[1] - 2 * GROW


def premultiplied_resize(im, size):
    arr = np.asarray(im).astype("float32")
    al = arr[..., 3:4] / 255.0
    arr[..., :3] *= al
    pm = Image.fromarray(arr.astype("uint8"), "RGBA").resize(size, Image.LANCZOS)
    arr = np.asarray(pm).astype("float32")
    al = arr[..., 3:4] / 255.0
    with np.errstate(divide="ignore", invalid="ignore"):
        arr[..., :3] = np.where(al > 0, arr[..., :3] / al, 0)
    return Image.fromarray(arr.clip(0, 255).astype("uint8"), "RGBA")


def place(im, ax, floor_y, scale):
    """縮小して 192×208 のセルに置く。足元を下端 PAD に、anchor_x を中央に。はみ出しは切る。"""
    w, h = max(1, round(im.width * scale)), max(1, round(im.height * scale))
    small = premultiplied_resize(im, (w, h))
    cell = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    ox = round(CW / 2 - ax * scale)
    oy = round(CH - PAD - floor_y * scale)
    # alpha_composite は負のオフセットを受け付けないので手で切る
    sx, sy = max(0, -ox), max(0, -oy)
    dx, dy = max(0, ox), max(0, oy)
    sub = small.crop((sx, sy, min(w, sx + CW - dx), min(h, sy + CH - dy)))
    if sub.width > 0 and sub.height > 0:
        cell.alpha_composite(sub, (dx, dy))
    return cell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="idle_1_<v>.png / sprite_1_<v>.png / sprite_2_<v>.png のあるフォルダ")
    ap.add_argument("--variant", required=True, choices=sorted(MAPPINGS))
    ap.add_argument("--out", required=True, help="出力フォルダ（pet.json と spritesheet.png を書く）")
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True, help="displayName")
    ap.add_argument("--reference", default=str(Path(__file__).resolve().parent.parent
                                               / "Sources/Enoki/Resources/DefaultSkin/spritesheet.png"),
                    help="身長を合わせる基準シート。既定は内蔵 DefaultSkin だが、これは"
                         "デモ用キャラクター（栞）のシートなので、朔と栞の差分を作るときは"
                         "元のシート（例: ~/.codex/pets/sakushio_pet/spritesheet.png）を明示すること")
    ap.add_argument("--no-webp", action="store_true")
    ap.add_argument("--idle-image", default=None,
                    help="idle_01 に使う単体絵を差し替える（例: renofa_in_match.png）。省略時は idle_1_<variant>.png")
    ap.add_argument("--static-idle", action="store_true",
                    help="idle 行のまばたき（idle_02 / idle_03）も --idle-image と同じ絵にして静止させる（試合局面ポーズ用）")
    args = ap.parse_args()

    src, out = Path(args.src).expanduser(), Path(args.out).expanduser()
    mapping = MAPPINGS[args.variant]

    # 基準の身長: 基準シートの row 0 / col 2（idle_02）
    ref = Image.open(args.reference).convert("RGBA")
    ref_h = content_height(ref.crop((2 * CW, 0, 3 * CW, CH)))

    # セルを集める
    cells = {}
    for n in (1, 2):
        for i, cell in enumerate(slice_sheet(find_source(src, f"sprite_{n}", args.variant))):
            cells[f"{n}-{i}"] = cell
    frames = {name: cells[label] for name, label in mapping.items()}
    idle_path = Path(args.idle_image).expanduser() if args.idle_image else find_source(src, "idle_1", args.variant)
    idle = Image.open(idle_path).convert("RGBA")
    bb = alpha_bbox(idle)
    frames["idle_01"] = (idle, (bb[0] + bb[2]) / 2, bb[3] - GROW)

    # シート側は idle_02 の身長、単体絵は idle_01 自身の身長で基準に合わせる
    sheet_scale = ref_h / content_height(frames["idle_02"][0])
    idle_scale = ref_h / content_height(frames["idle_01"][0])
    print(f"基準身長 {ref_h}px / シート倍率 {sheet_scale:.4f} / idle_01 倍率 {idle_scale:.4f}")

    idle_names = {"idle_01"}
    if args.static_idle:
        # まばたきのコマも同じ絵にして、局面ポーズ（横断幕・フラッグ）が一瞬消えないようにする
        frames["idle_02"] = frames["idle_01"]
        frames["idle_03"] = frames["idle_01"]
        idle_names |= {"idle_02", "idle_03"}

    placed = {}
    for name, (im, ax, fy) in frames.items():
        scale = idle_scale if name in idle_names else sheet_scale
        placed[name] = place(im, ax, fy, scale)
        # はみ出し警告
        w, h = round(im.width * scale), round(im.height * scale)
        b = alpha_bbox(im)
        if b:
            left = CW / 2 - (ax - b[0]) * scale
            right = CW / 2 + (b[2] - ax) * scale
            top = CH - PAD - (fy - b[1]) * scale
            if left < 0 or right > CW or top < 0:
                print(f"  注意: {name} はセルからはみ出します (left={left:.0f} right={right:.0f} top={top:.0f})")

    atlas = Image.new("RGBA", (COLS * CW, ROWS * CH), (0, 0, 0, 0))
    for r, (state, names) in enumerate(ROW_MAP):
        for c, n in enumerate(names):
            atlas.alpha_composite(placed[n], (c * CW, r * CH))
    arr = np.asarray(atlas).copy()
    arr[arr[..., 3] == 0, :3] = 0
    atlas = Image.fromarray(arr, "RGBA")

    out.mkdir(parents=True, exist_ok=True)
    atlas.save(out / "spritesheet.png", optimize=True)
    if not args.no_webp:
        atlas.save(out / "spritesheet.webp", lossless=True, quality=100, method=6, exact=True)
    json.dump({"id": args.id, "displayName": args.name,
               "description": f"朔と栞 {args.variant} variant (generated by scripts/build_variant_atlas.py)",
               "spritesheetPath": "spritesheet.png"},
              open(out / "pet.json", "w"), ensure_ascii=False, indent=2)

    # QA 一覧（リポジトリには入れない想定。--out の隣の qa/ に置く）
    qa_dir = out / "qa"
    qa_dir.mkdir(exist_ok=True)
    qa = Image.new("RGBA", atlas.size, (240, 240, 240, 255))
    qa.alpha_composite(atlas)
    d = ImageDraw.Draw(qa)
    for r, (state, names) in enumerate(ROW_MAP):
        for c in range(COLS):
            d.rectangle([c * CW, r * CH, (c + 1) * CW - 1, (r + 1) * CH - 1], outline=(180, 180, 180, 255))
        d.text((4, r * CH + 4), f"{r}: {state}", fill=(200, 0, 0, 255))
        for c, n in enumerate(names):
            d.text((c * CW + 4, r * CH + CH - 14), n, fill=(0, 0, 160, 255))
    qa.convert("RGB").save(qa_dir / "contact-sheet.png")
    print("done:", out / "spritesheet.png", atlas.size)


if __name__ == "__main__":
    main()
