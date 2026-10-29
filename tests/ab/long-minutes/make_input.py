# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regenerate input/protokolle.md (committed, so every trial starts from the same bytes).

Twenty-four monthly board meetings of a sports club, about 50k tokens of
seeded routine minutes, with spending decisions planted among proposals that
were rejected or put off, one put off and later decided at a lower amount,
one decided and later reversed, and treasurer's balances as noise. The
grader imports DECIDED, NOT_DECIDED and REVERSED from here.

    python3 tests/ab/long-minutes/make_input.py tests/ab/long-minutes/input/protokolle.md
"""

import datetime
import random
import sys


def second_tuesday(year, month):
    d = datetime.date(year, month, 8)
    return d + datetime.timedelta(days=(1 - d.weekday()) % 7)


MEETINGS = [second_tuesday(y, m) for y in (2024, 2025) for m in range(1, 13)]
D = {(d.year, d.month): d for d in MEETINGS}

# (meeting, purpose keyword, amount, text)
DECIDED = [
    (D[2024, 2], "Flutlicht", 18500, "Der Vorstand beschließt einstimmig, für die Erneuerung der Flutlichtanlage auf Platz 2 "
     "18.500 € freizugeben. Den Auftrag erhält die Firma Elektro Brandt, deren Angebot das günstigste war."),
    (D[2024, 5], "Trainingslager", 3200, "Für das Trainingslager der A- und B-Jugend in den Sommerferien gewährt der Verein "
     "einen Zuschuss von 3.200 €. Beschlossen mit 6 Ja-Stimmen bei einer Enthaltung."),
    (D[2024, 9], "Vereinsfest", 4750, "Das Vereinsfest zum 100-jährigen Bestehen soll im Juni 2025 stattfinden. Der "
     "Vorstand bewilligt dafür ein Budget von 4.750 € (einstimmig)."),
    (D[2024, 11], "Trikots", 2940, "Beschluss: Für neue Trikotsätze der beiden Seniorenmannschaften werden 2.940 € "
     "ausgegeben. Der Sponsor übernimmt den Druck."),
    (D[2025, 4], "Rasen", 26000, "Nach dem neuen Angebot beschließt der Vorstand die Sanierung des Rasens auf Platz 1 "
     "für 26.000 €. Die Arbeiten beginnen nach dem letzten Heimspiel."),
    (D[2025, 10], "Küche", 7380, "Die Küche im Vereinsheim wird erneuert; der Vorstand gibt dafür 7.380 € frei "
     "(5 Ja, 2 Nein)."),
]
NOT_DECIDED = [
    (D[2024, 6], 34000, "Der Antrag der Jugendabteilung, einen Kleinbus für 34.000 € anzuschaffen, wird mit 3 zu 4 "
     "Stimmen abgelehnt. Die Jugendabteilung prüft stattdessen ein Leasingangebot."),
    (D[2025, 1], 1800, "Ein Zuschuss von 1.800 € für die Skifahrt der Altherren wird abgelehnt, weil die Fahrt keine "
     "Vereinsveranstaltung ist."),
    (D[2025, 3], 31000, "Für die Rasensanierung auf Platz 1 liegt ein Angebot über 31.000 € vor. Der Vorstand hält es für "
     "zu hoch und vertagt die Entscheidung, bis ein zweites Angebot vorliegt."),
    (D[2025, 7], 5600, "Der Vorschlag, die Website für 5.600 € von einer Agentur neu gestalten zu lassen, wird vertagt; "
     "zunächst soll ein Mitglied ein eigenes Konzept vorlegen."),
]
REVERSED = (D[2025, 3], "Vereinsfest", "Der Beschluss vom {:%d.%m.%Y} über das Budget für das Vereinsfest wird aufgehoben: "
            "Wegen der Rasensanierung kann das Fest 2025 nicht auf dem Vereinsgelände stattfinden und entfällt. Das "
            "Jubiläum wird im kleineren Rahmen im Vereinsheim gefeiert.".format(D[2024, 9]))

PEOPLE = ["Petra Lindemann (1. Vorsitzende)", "Jürgen Hoffmann (2. Vorsitzender)", "Aylin Demir (Kassiererin)",
          "Klaus Brüggemann (Schriftführer)", "Monika Weiß (Jugendwartin)", "Stefan Kowalski (Sportwart)",
          "Hannelore Schmitz (Beisitzerin)"]
TOPICS = {
    "Mitglieder": ["Die Mitgliederzahl liegt bei {n} Personen, davon {j} Kinder und Jugendliche.",
                   "Im letzten Monat gab es {a} Eintritte und {b} Austritte.",
                   "Die Beitragseinzüge sind ohne Rücklastschriften gelaufen.",
                   "Frau Demir erinnert daran, dass Adressänderungen bitte schriftlich mitzuteilen sind.",
                   "Für langjährige Mitglieder soll bei der nächsten Jahreshauptversammlung eine Ehrung stattfinden."],
    "Sportbetrieb": ["Die erste Mannschaft steht derzeit auf Platz {p} der Tabelle.",
                     "Herr Kowalski berichtet, dass die Trainingszeiten in der Halle unverändert bleiben.",
                     "Die Damenmannschaft sucht weiterhin eine Co-Trainerin.",
                     "Das Hallenturnier im Winter ist bereits zu zwei Dritteln ausgebucht.",
                     "Mehrere Spiele mussten wegen der Witterung verlegt werden.",
                     "Die Schiedsrichterbeobachtung lief ohne Beanstandungen."],
    "Jugend": ["Frau Weiß berichtet aus der Jugendabteilung: {t} Teams sind im Spielbetrieb.",
               "Die Kooperation mit der Grundschule an der Bergstraße läuft gut.",
               "Für das Ferienprogramm haben sich bereits zahlreiche Kinder angemeldet.",
               "Die Jugendleiterkarten von zwei Betreuern müssen verlängert werden.",
               "Elternabende finden künftig zweimal im Jahr statt."],
    "Anlage": ["Der Platzwart meldet, dass die Bewässerung zuverlässig arbeitet.",
               "Die Umkleiden wurden gründlich gereinigt; die Duschköpfe sollen getauscht werden.",
               "Am Zaun hinter dem Tor ist ein Stück beschädigt, das Herr Hoffmann reparieren lässt.",
               "Die Parkplatzsituation bei Heimspielen bleibt angespannt.",
               "Der Geräteraum wurde aufgeräumt und neu beschriftet."],
    "Verschiedenes": ["Herr Brüggemann bittet um Beiträge für die Vereinszeitung.",
                      "Der Vorstand dankt allen Helferinnen und Helfern des letzten Heimspieltags.",
                      "Die Vereinswebsite wurde um einen Terminkalender ergänzt.",
                      "Für die Weihnachtsfeier wird noch ein Termin gesucht.",
                      "Die nächste Begehung mit der Stadt ist für das Frühjahr geplant.",
                      "Es gibt keine weiteren Wortmeldungen."],
}
DEPARTMENTS = {
    "Tennis": ["Die Tennisabteilung hat {a} neue Mitglieder gewonnen.", "Die Plätze wurden zum Saisonstart neu abgezogen.",
               "Das Mixed-Turnier fand mit {t} Paaren statt.", "Die Hallenbuchung für den Winter ist abgeschlossen.",
               "Die Medenspielmannschaft der Herren 40 spielt um den Aufstieg.", "Der Trainervertrag wurde um ein Jahr verlängert.",
               "Die Ballmaschine ist repariert und wieder im Einsatz.", "Die Platzbelegung läuft jetzt über die Online-Buchung."],
    "Turnen": ["Die Turnabteilung meldet volle Kurse beim Kinderturnen.", "Für das Eltern-Kind-Turnen wird eine weitere Übungsleiterin gesucht.",
               "Die Geräte in der kleinen Halle wurden vom TÜV geprüft.", "Beim Gaukinderturnfest gingen {t} Kinder an den Start.",
               "Der Seniorenkurs am Donnerstag ist gut besucht.", "Die Abteilung plant eine Vorführung beim Weihnachtsmarkt.",
               "Zwei Übungsleiterinnen haben ihre Lizenz erneuert.", "Die Matten sollen im nächsten Jahr ersetzt werden."],
    "Leichtathletik": ["Die Leichtathletinnen und Leichtathleten trainieren dienstags und freitags.",
                       "Beim Kreissportfest gab es {a} Podestplätze.", "Die Laufgruppe trifft sich sonntags um 9 Uhr am Vereinsheim.",
                       "Die Sportabzeichenabnahme findet im Sommer jeden Mittwoch statt.",
                       "Der Volkslauf im Herbst hatte {n} Teilnehmende.", "Die Weitsprunggrube muss aufgefüllt werden.",
                       "Die Zeitmessanlage wird mit dem Nachbarverein geteilt.", "Für den Winter ist ein Crosslauf geplant."],
    "Tischtennis": ["Die Tischtennisabteilung spielt mit vier Mannschaften.", "Die Jugend trainiert jetzt auch samstags.",
                    "Zwei Tische wurden aus Spenden ersetzt.", "Die Vereinsmeisterschaft gewann erneut die Titelverteidigerin.",
                    "Das Ranglistenturnier war gut organisiert.", "Die Abteilung beteiligt sich am Ferienprogramm.",
                    "Die Netzgarnituren sind abgenutzt und werden getauscht.", "Der Spielbetrieb läuft ohne Ausfälle."],
    "Gesundheitssport": ["Der Rückenkurs ist bis zum Jahresende ausgebucht.", "Die Krankenkassen erkennen den Kurs weiterhin an.",
                         "Die Abteilung bietet ab dem Herbst einen Yogakurs an.", "Die Teilnehmerlisten werden jetzt digital geführt.",
                         "Der Reha-Sport läuft mit {t} Gruppen.", "Eine Übungsleiterin geht in Elternzeit; eine Vertretung ist gefunden.",
                         "Die Nordic-Walking-Gruppe trifft sich auch im Winter.", "Für den Kurs am Montag gibt es eine Warteliste."],
}


def para(rnd, topic, k):
    bank = TOPICS.get(topic) or DEPARTMENTS[topic]
    s = rnd.sample(bank, min(k, len(bank)))
    return " ".join(x.format(n=rnd.randint(410, 470), j=rnd.randint(150, 190), a=rnd.randint(1, 9),
                             b=rnd.randint(0, 5), p=rnd.randint(1, 12), t=rnd.randint(9, 12)) for x in s)


def main(out):
    rnd = random.Random(1924)
    planted = {}
    for m, _, _, text in DECIDED:
        planted.setdefault(m, []).append(text)
    for m, _, text in NOT_DECIDED:
        planted.setdefault(m, []).append(text)
    planted.setdefault(REVERSED[0], []).append(REVERSED[2])
    md = ["# Protokolle des Vorstands, SV Grün-Weiß Musterhausen 1925 e. V.", ""]
    balance = 21480.55
    for meeting in MEETINGS:
        balance += rnd.uniform(-1800, 2100)
        present = rnd.sample(PEOPLE, rnd.randint(5, 7))
        md += [f"## Vorstandssitzung am {meeting:%d.%m.%Y}", "",
               f"Beginn 19:{rnd.choice(['00', '05', '15', '30'])} Uhr, Vereinsheim. Anwesend: " + ", ".join(present) + ".",
               f"Protokoll: Klaus Brüggemann. Das Protokoll der letzten Sitzung wird ohne Änderungen genehmigt.", "",
               "### TOP 1: Bericht der Kasse", "",
               f"Frau Demir legt den Kassenbericht vor. Der Kassenstand beträgt {balance:,.2f} €".replace(",", "X")
               .replace(".", ",").replace("X", ".") + ". " + para(rnd, "Mitglieder", 3), ""]
        for i, topic in enumerate(["Sportbetrieb", "Jugend", "Anlage"], 2):
            md += [f"### TOP {i}: {topic}", "", para(rnd, topic, 5), "", para(rnd, topic, 4), "", para(rnd, topic, 3), ""]
        md += ["### TOP 5: Berichte aus den Abteilungen", ""]
        for dept in DEPARTMENTS:
            md += [f"**{dept}.** " + para(rnd, dept, 5) + " " + para(rnd, dept, 3), ""]
        if meeting in planted:
            md += ["### TOP 6: Anträge und Beschlüsse", ""]
            for text in planted[meeting]:
                md += [para(rnd, "Verschiedenes", 1) + " " + text, ""]
        md += ["### TOP 7: Verschiedenes", "", para(rnd, "Verschiedenes", 4), "", para(rnd, "Mitglieder", 2), "",
               f"Ende der Sitzung 21:{rnd.randint(10, 55)} Uhr.", ""]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(md))


if __name__ == "__main__":
    main(sys.argv[1])
