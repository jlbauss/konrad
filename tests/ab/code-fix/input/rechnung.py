"""Rechnungssummen aus einer Positionsliste (CSV mit Semikolon, deutsche Zahlen).

    python rechnung.py positionen.csv
"""

import csv
import sys

MWST = 0.19
RABATT_AB = 500  # ab diesem Nettobetrag gibt es Rabatt
RABATT = 0.03


def parse_betrag(text):
    """'1.234,50' -> 1234.5"""
    return float(text.strip().replace(",", "."))


def zeile(menge, preis):
    """Zeilensumme, kaufmännisch auf Cent gerundet."""
    return round(menge * preis, 2)


def summen(positionen):
    netto = sum(zeile(m, p) for m, p in positionen)
    if netto > RABATT_AB:
        netto = round(netto * (1 - RABATT), 2)
    mwst = round(netto * MWST, 2)
    return {"netto": netto, "mwst": mwst, "brutto": round(netto + mwst, 2)}


def lese(pfad):
    with open(pfad, encoding="utf-8") as f:
        return [(parse_betrag(r["Menge"]), parse_betrag(r["Einzelpreis"])) for r in csv.DictReader(f, delimiter=";")]


if __name__ == "__main__":
    for name, wert in summen(lese(sys.argv[1])).items():
        print(f"{name}: {wert:.2f}")
