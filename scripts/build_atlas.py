#!/usr/bin/env python3
"""ポーズ画像のフォルダから Codex Pet 形式のスプライトシートを作る（汎用）。

  python3 scripts/build_atlas.py --src ~/Desktop/my_poses --out ~/.codex/pets/my_pet \
      --id my_pet --name "わたしのキャラクター"

- 1 ポーズ = 1 枚の PNG（透過）を、8 列 × 9 行のアトラスに詰めるだけです。**描き直しはしません。**
- 全コマ共通の切り出し範囲と縮小率を使うので、**どのコマでも身長と立ち位置が揃います**
  （状態が切り替わっても絵が跳ねません）。足元はセル下端から --pad px、水平は中央に置きます。
- 足りないポーズは `--map` の fallback（既定では idle の絵）で埋めるので、
  数枚しか無くても動くスプライトセットになります。
- 2 人以上を 1 コマに入れたいときは `--cell 320x208` のようにセルを広げてください
  （`pet.json` に `mascot.grid` を書き出すので、アプリ側の設定は不要です）。
  そのとき、吹き出しの `anchor` の目安も推定して表示します。

依存: pip3 install pillow numpy
"""
import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
    import numpy as np
except ImportError:  # pragma: no cover - 実行時の案内
    sys.exit("pillow と numpy が必要です: pip3 install pillow numpy")

COLUMNS, ROWS = 8, 9
DEFAULT_CELL = (192, 208)
DEFAULT_PAD = 2
ALPHA_THRESHOLD = 16      # これ以下のアルファは「余白のノイズ」とみなす

# 既定の行割り当て。EnokiCore の CodexPetDefaults.rowSpecs と同じ 9 行構成で、
# ポーズ名は Codex の pet 素材でよく使われている名前にしてある。
# `--map` を渡せば、この表を自分のファイル名で置き換えられる。
DEFAULT_ROW_MAP = [
    ("idle",          ["normal", "normal", "wink_1", "wink_2", "wink_1", "normal"]),
    ("running-right", ["drag", "look_right"] * 4),
    ("running-left",  ["drag", "look_left"] * 4),
    ("waving",        ["touch", "wave_1", "wave_2", "wave_1"]),
    ("jumping",       ["look_top", "jump", "success_1", "success_2", "normal"]),
    ("failed",        ["failure_1", "failure_2"] * 4),
    ("waiting",       ["waiting_1", "waiting_2", "waiting_1", "waiting_2", "sleep_1", "sleep_2"]),
    ("running",       ["work_1", "work_2", "work_3"] * 2),
    ("review",        ["review", "review_2"] * 3),
]
DEFAULT_FALLBACK = "normal"

IMAGE_SUFFIXES = (".png", ".webp", ".jpg", ".jpeg")


def parse_cell(value):
    """'320x208' → (320, 208)"""
    try:
        width, height = value.lower().split("x")
        cell = (int(width), int(height))
    except ValueError:
        raise argparse.ArgumentTypeError(f"--cell は 幅x高さ の形式で指定してください（例: 192x208）: {value}")
    if cell[0] < 1 or cell[1] < 1:
        raise argparse.ArgumentTypeError("--cell は 1 以上の数値で指定してください")
    return cell


def load_row_map(path):
    """`--map` の JSON を読む。

    {
      "fallback": "stand",
      "rows": { "idle": ["stand", "blink"], "waving": ["hello_1", "hello_2"] }
    }

    書かなかった行は既定の割り当てのまま（そこに無いポーズは fallback で埋まる）。
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        sys.exit(f"{path}: ルートがオブジェクトではありません")
    rows = data.get("rows", {})
    if not isinstance(rows, dict):
        sys.exit(f"{path}: rows はオブジェクトで書いてください")
    row_map = []
    for state, frames in DEFAULT_ROW_MAP:
        override = rows.get(state)
        if override is None:
            row_map.append((state, list(frames)))
            continue
        if not isinstance(override, list) or not override:
            sys.exit(f"{path}: rows.{state} は 1 つ以上のポーズ名の配列で書いてください")
        row_map.append((state, [str(name) for name in override[:COLUMNS]]))
    unknown = set(rows) - {state for state, _ in DEFAULT_ROW_MAP}
    if unknown:
        print(f"!! 知らない行名は無視します: {', '.join(sorted(unknown))}")
    return row_map, str(data.get("fallback") or DEFAULT_FALLBACK)


def find_pose(src, name):
    """ポーズ名から画像ファイルを探す（拡張子は問わない）"""
    for suffix in IMAGE_SUFFIXES:
        path = src / f"{name}{suffix}"
        if path.exists():
            return path
    return None


def alpha_bbox(image, threshold=ALPHA_THRESHOLD):
    mask = np.asarray(image)[..., 3] > threshold
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def premultiplied_resize(image, size):
    """乗算済みアルファで縮小する（境界に黒い縁が出ないように）"""
    arr = np.asarray(image).astype("float32")
    alpha = arr[..., 3:4] / 255.0
    arr[..., :3] *= alpha
    small = Image.fromarray(arr.astype("uint8"), "RGBA").resize(size, Image.LANCZOS)
    arr = np.asarray(small).astype("float32")
    alpha = arr[..., 3:4] / 255.0
    with np.errstate(divide="ignore", invalid="ignore"):
        arr[..., :3] = np.where(alpha > 0, arr[..., :3] / alpha, 0)
    return Image.fromarray(arr.clip(0, 255).astype("uint8"), "RGBA")


def estimate_anchors(cell_image, cell_width, gap_ratio=0.04):
    """1 コマの絵から、立っている人（かたまり）の中心を推定して anchor を返す。

    アルファのある列を左から見て、`gap_ratio` × セル幅 より広い透明の切れ目で区切る。
    2 人以上を 1 コマに描いたときの `dialogue.json` の `speakers[].anchor` の目安になる。
    """
    mask = np.asarray(cell_image)[..., 3] > ALPHA_THRESHOLD
    columns = mask.any(axis=0)
    gap = max(1, int(cell_width * gap_ratio))
    clusters, start, empty = [], None, 0
    for x, filled in enumerate(columns):
        if filled:
            if start is None:
                start = x
            empty = 0
        elif start is not None:
            empty += 1
            if empty >= gap:
                clusters.append((start, x - empty + 1))
                start, empty = None, 0
    if start is not None:
        clusters.append((start, len(columns)))
    return [round((lo + hi) / 2 / cell_width, 3) for lo, hi in clusters]


def build(args):
    src = Path(args.src).expanduser()
    out = Path(args.out).expanduser()
    if not src.is_dir():
        sys.exit(f"--src が見つかりません: {src}")

    row_map, fallback_name = (load_row_map(args.map) if args.map
                              else ([(state, list(frames)) for state, frames in DEFAULT_ROW_MAP], DEFAULT_FALLBACK))
    cell_width, cell_height = args.cell
    pad = args.pad

    # --- ポーズ画像を集める（足りないものは fallback で埋める） ---------------
    wanted = []
    for _, frames in row_map:
        for name in frames:
            if name not in wanted:
                wanted.append(name)

    images, missing = {}, []
    for name in wanted:
        path = find_pose(src, name)
        if path is None:
            missing.append(name)
            continue
        images[name] = Image.open(path).convert("RGBA")

    if not images:
        sys.exit(f"{src} にポーズ画像が 1 枚も見つかりません（探した名前: {', '.join(wanted[:8])} …）")

    fallback = images.get(fallback_name) or images[next(iter(images))]
    fallback_label = fallback_name if fallback_name in images else next(iter(images))
    if missing:
        print(f"-- 見つからないポーズは「{fallback_label}」で埋めます（{len(missing)} 個）: {', '.join(missing)}")
    for name in missing:
        images[name] = fallback

    # --- 全コマ共通の切り出し範囲と縮小率 -------------------------------------
    boxes = [alpha_bbox(image) for image in images.values()]
    boxes = [box for box in boxes if box is not None]
    if not boxes:
        sys.exit("すべての画像が透明です。透過 PNG になっているか確認してください。")
    x0 = min(box[0] for box in boxes)
    y0 = min(box[1] for box in boxes)
    x1 = max(box[2] for box in boxes)
    y1 = max(box[3] for box in boxes)
    union_w, union_h = x1 - x0, y1 - y0
    scale = min((cell_width - 2 * pad) / union_w, (cell_height - 2 * pad) / union_h)
    target = (max(1, round(union_w * scale)), max(1, round(union_h * scale)))
    print(f"-- 切り出し {union_w}x{union_h}px を {target[0]}x{target[1]}px へ（scale={scale:.4f}）")

    placed = {}
    for name, image in images.items():
        if name in placed:
            continue
        placed[name] = premultiplied_resize(image.crop((x0, y0, x1, y1)), target)

    # --- アトラスに並べる（足元を下端 pad に、水平は中央に）-------------------
    atlas = Image.new("RGBA", (COLUMNS * cell_width, ROWS * cell_height), (0, 0, 0, 0))
    offset_x = (cell_width - target[0]) // 2
    offset_y = cell_height - pad - target[1]
    for row, (_, frames) in enumerate(row_map):
        for column, name in enumerate(frames[:COLUMNS]):
            atlas.alpha_composite(placed[name], (column * cell_width + offset_x, row * cell_height + offset_y))

    # 完全に透明な画素の RGB を 0 にしておく（縁のにじみ防止）
    arr = np.asarray(atlas).copy()
    arr[arr[..., 3] == 0, :3] = 0
    atlas = Image.fromarray(arr, "RGBA")

    # --- 書き出し -------------------------------------------------------------
    out.mkdir(parents=True, exist_ok=True)
    sheet_name = "spritesheet.png"
    atlas.save(out / sheet_name, optimize=True)
    if args.webp:
        atlas.save(out / "spritesheet.webp", lossless=True, quality=100, method=6, exact=True)

    manifest = {
        "id": args.id,
        "displayName": args.name,
        "spritesheetPath": sheet_name,
    }
    if args.description:
        manifest["description"] = args.description
    if (cell_width, cell_height) != DEFAULT_CELL:
        # 既定（192x208）以外のセルはアプリに教える必要がある
        manifest["mascot"] = {
            "grid": {"columns": COLUMNS, "rows": ROWS, "cellWidth": cell_width, "cellHeight": cell_height}
        }
    (out / "pet.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # --- 吹き出しの anchor の目安 ---------------------------------------------
    idle_cell = atlas.crop((0, 0, cell_width, cell_height))
    anchors = estimate_anchors(idle_cell, cell_width)
    if len(anchors) >= 2:
        print(f"-- 1 コマに {len(anchors)} 人ぶんのかたまりが見えます。dialogue.json の speakers の目安:")
        speakers = [{"id": f"speaker{i + 1}", "displayName": f"話者{i + 1}", "anchor": anchor}
                    for i, anchor in enumerate(anchors)]
        print(json.dumps({"speakers": speakers}, ensure_ascii=False, indent=2))
    else:
        print("-- 1 人用のセットとして作りました（dialogue.json の speakers は 1 人ぶん、吹き出しは中央に出ます）")

    # --- QA 用の一覧（任意）---------------------------------------------------
    if args.qa:
        qa_dir = out / "qa"
        qa_dir.mkdir(exist_ok=True)
        sheet = Image.new("RGBA", atlas.size, (240, 240, 240, 255))
        sheet.alpha_composite(atlas)
        draw = ImageDraw.Draw(sheet)
        for row, (state, frames) in enumerate(row_map):
            for column in range(COLUMNS):
                draw.rectangle([column * cell_width, row * cell_height,
                                (column + 1) * cell_width - 1, (row + 1) * cell_height - 1],
                               outline=(180, 180, 180, 255))
            draw.text((4, row * cell_height + 4), f"{row}: {state}", fill=(200, 0, 0, 255))
            for column, name in enumerate(frames[:COLUMNS]):
                draw.text((column * cell_width + 4, row * cell_height + cell_height - 14), name,
                          fill=(0, 0, 160, 255))
        sheet.convert("RGB").save(qa_dir / "contact-sheet.png")
        (qa_dir / "row-map.json").write_text(json.dumps(
            {"rows": [{"row": row, "state": state, "frames": frames[:COLUMNS]}
                      for row, (state, frames) in enumerate(row_map)],
             "cell": [cell_width, cell_height], "pad": pad, "scale": scale,
             "missing": missing, "anchors": anchors},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"-- QA: {qa_dir/'contact-sheet.png'}")

    print(f"完成: {out}  （{COLUMNS}列 × {ROWS}行 / 1 コマ {cell_width}x{cell_height}px / 画像 {atlas.width}x{atlas.height}px）")
    print(f"  試す: ENOKI_SKIN_DIR={out} swift run Enoki")


def main():
    parser = argparse.ArgumentParser(
        description="ポーズ画像のフォルダから Codex Pet 形式のスプライトシートを作る",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="既定のポーズ名: " + ", ".join(sorted({n for _, fr in DEFAULT_ROW_MAP for n in fr})))
    parser.add_argument("--src", required=True, help="ポーズ画像（透過 PNG）が入ったフォルダ")
    parser.add_argument("--out", required=True, help="出力フォルダ（pet.json と spritesheet.png を書く）")
    parser.add_argument("--id", default=None, help="pet.json の id（既定: 出力フォルダ名）")
    parser.add_argument("--name", default=None, help="pet.json の displayName（既定: id と同じ）")
    parser.add_argument("--description", default=None, help="pet.json の description（省略可）")
    parser.add_argument("--map", default=None,
                        help="行とポーズ名の対応を書いた JSON（自分のファイル名で作る場合）")
    parser.add_argument("--cell", type=parse_cell, default=DEFAULT_CELL, metavar="WxH",
                        help="1 コマの大きさ（既定: 192x208）。2 人以上なら 320x208 など横に広げる")
    parser.add_argument("--pad", type=int, default=DEFAULT_PAD,
                        help="セル内の余白 px（足元の位置。既定: 2）")
    parser.add_argument("--webp", action="store_true", help="spritesheet.webp も書き出す")
    parser.add_argument("--qa", action="store_true", help="qa/contact-sheet.png（確認用の一覧）も書き出す")
    args = parser.parse_args()

    if args.id is None:
        args.id = Path(args.out).expanduser().name
    if args.name is None:
        args.name = args.id
    if args.pad < 0 or args.pad * 2 >= min(args.cell):
        sys.exit("--pad が大きすぎます")
    build(args)


if __name__ == "__main__":
    main()
