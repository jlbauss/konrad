import unittest

from rechnung import lese, parse_betrag, summen, zeile


class TestRechnung(unittest.TestCase):
    def test_betrag_einfach(self):
        self.assertEqual(parse_betrag("12,50"), 12.5)

    def test_betrag_mit_tausenderpunkt(self):
        self.assertEqual(parse_betrag("1.234,50"), 1234.5)

    def test_zeile_rundet_kaufmaennisch(self):
        self.assertEqual(zeile(3, 0.835), 2.51)

    def test_ohne_rabatt(self):
        self.assertEqual(summen([(2, 100.0)]), {"netto": 200.0, "mwst": 38.0, "brutto": 238.0})

    def test_rabatt_ab_genau_500(self):
        self.assertEqual(summen([(1, 500.0)])["netto"], 485.0)

    def test_datei(self):
        self.assertEqual(summen(lese("positionen.csv")), {"netto": 1426.14, "mwst": 270.97, "brutto": 1697.11})


if __name__ == "__main__":
    unittest.main()
