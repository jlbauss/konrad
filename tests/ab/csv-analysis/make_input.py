# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regenerate input/verkaeufe.csv (committed, so every trial starts from the same bytes).

Seeded random sales for 2025: four regions, eight products, a December peak
and clear gaps between the products, so the answers are unambiguous. The
grader computes them from the committed CSV, not from this script.

    python3 tests/ab/csv-analysis/make_input.py tests/ab/csv-analysis/input/verkaeufe.csv
"""

import datetime
import random
import sys

PRODUCTS = {"Kaffeemaschine Pro": 289.0, "Milchaufschäumer": 49.9, "Espressomühle": 159.0, "Wasserkocher": 39.9,
            "Siebträger Basic": 449.0, "Entkalker 6er": 17.5, "Thermobecher": 24.9, "Kapselhalter": 19.9}
WEIGHT = {"Kaffeemaschine Pro": 5, "Milchaufschäumer": 9, "Espressomühle": 6, "Wasserkocher": 7,
          "Siebträger Basic": 2, "Entkalker 6er": 10, "Thermobecher": 8, "Kapselhalter": 4}
REGIONS = {"Nord": 1.0, "Süd": 1.35, "West": 1.15, "Ost": 0.7}


def main(out):
    rnd = random.Random(2025)
    rows = []
    day = datetime.date(2025, 1, 1)
    while day.year == 2025:
        season = 1.6 if day.month == 12 else 1.15 if day.month == 11 else 0.85 if day.month in (7, 8) else 1.0
        for region, size in REGIONS.items():
            for _ in range(rnd.choices((0, 1, 2), (0.45, 0.4, 0.15))[0]):
                if rnd.random() > size * season / 1.6 * 0.9:
                    continue
                product = rnd.choices(list(PRODUCTS), list(WEIGHT.values()))[0]
                qty = rnd.randint(1, 4) * (3 if product in ("Entkalker 6er", "Thermobecher") else 1)
                price = PRODUCTS[product]
                rows.append(f"{day.isoformat()},{region},{product},{qty},{price:.2f},{qty * price:.2f}")
        day += datetime.timedelta(days=1)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("datum,region,produkt,menge,einzelpreis,umsatz\n" + "\n".join(rows) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
