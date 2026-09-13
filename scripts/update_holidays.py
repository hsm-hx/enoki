#!/usr/bin/env python3
"""内閣府が公開している「国民の祝日」CSV を UTF-8 の JSON に変換して同梱リソースを更新する。

  python3 scripts/update_holidays.py                    # 取得して Sources/Enoki/Resources/Holidays/jp-holidays.json を更新
  python3 scripts/update_holidays.py --csv local.csv    # ダウンロード済みの CSV から作る
  python3 scripts/update_holidays.py --check            # 更新せず差分だけ表示する

- 取得元: https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv（Shift_JIS, 1955 年〜翌年分）
  列は「国民の祝日・休日月日, 国民の祝日・休日名称」で、振替休日・国民の休日も入っています。
- 内閣府のデータは**翌年分までしか載りません**。年に一度（新しい年の分が出る秋ごろ）実行してください。
  データに無い年はアプリ側（`JapaneseHolidays`）が現行ルールで計算して補います。
- 依存は Python 標準ライブラリだけです（アプリ本体は一切通信しません。これは開発時のスクリプトです）。
"""
import argparse
import csv
import io
import json
import sys
import urllib.request
from datetime import date, datetime
from pathlib import Path

CSV_URL = "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "Sources/Enoki/Resources/Holidays/jp-holidays.json"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "enoki-update-holidays/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def parse(raw: bytes) -> dict:
    """Shift_JIS の CSV → {"yyyy-mm-dd": "名前"}（日付順）"""
    text = raw.decode("shift_jis")
    reader = csv.reader(io.StringIO(text))
    header = next(reader, None)
    if header is None or "月日" not in header[0]:
        raise SystemExit(f"CSV の見出しが想定と違います: {header}")

    holidays = {}
    for row in reader:
        if len(row) < 2:
            continue
        raw_date, name = row[0].strip(), row[1].strip()
        if not raw_date or not name:
            continue
        try:
            parsed = datetime.strptime(raw_date, "%Y/%m/%d").date()
        except ValueError:
            print(f"  日付を読めない行を飛ばします: {row}", file=sys.stderr)
            continue
        holidays[parsed.isoformat()] = name
    return dict(sorted(holidays.items()))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--csv", type=Path, help="ダウンロード済みの CSV（省略時は内閣府から取得）")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"出力先 JSON（既定: {DEFAULT_OUT}）")
    parser.add_argument("--check", action="store_true", help="書き込まずに差分だけ表示する")
    args = parser.parse_args()

    raw = args.csv.read_bytes() if args.csv else fetch(CSV_URL)
    holidays = parse(raw)
    if not holidays:
        raise SystemExit("祝日を 1 件も読めませんでした（取得に失敗した可能性があります）")

    years = sorted({key[:4] for key in holidays})
    payload = {
        "schema_version": 1,
        "source": CSV_URL,
        "updated_at": date.today().isoformat(),
        "first_year": int(years[0]),
        "last_year": int(years[-1]),
        "holidays": holidays,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"

    old = json.loads(args.out.read_text(encoding="utf-8")) if args.out.exists() else {"holidays": {}}
    added = sorted(set(holidays) - set(old["holidays"]))
    removed = sorted(set(old["holidays"]) - set(holidays))
    print(f"{len(holidays)} 件 ({years[0]}〜{years[-1]})  追加 {len(added)} 件 / 削除 {len(removed)} 件")
    for key in added[:20]:
        print(f"  + {key} {holidays[key]}")
    for key in removed[:20]:
        print(f"  - {key} {old['holidays'][key]}")

    if args.check:
        return 0
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    print(f"書き出しました: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
