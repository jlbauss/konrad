# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Blind judging for the A/B harness; scripts/ab-judge.sh runs it in a konrad image.

blind:  each pair of runs (a-n, b-n) of a results dir becomes two packets,
        X/Y swapped, under random ids: the task, its input, and per side
        every deliverable as page renders, text and speaker notes, never the
        file itself or the agent's notes, which could say how it was made.
        The key goes into the results dir, the packets and the batches (one
        task and one order per batch, so no judge sees both halves of a
        pair) into a judge dir beside it.
report: unblinds the verdict.json files the judges wrote, combines both
        orders (a pair counts for a side only when both agree) and writes
        judge.md and a self-contained report.html with the graded checks,
        the verdicts and the clearest pairs side by side.
"""

import argparse
import base64
import html
import json
import random
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

DOCS = {".docx", ".pptx", ".xlsx", ".pdf"}
CRITERIA = ("request", "fidelity", "presentation")
MAX_PAGES = 12


def deliverables(ws, inputs):
    """Office files and PDFs the run left in its workspace, other than unchanged inputs."""
    if not ws.is_dir():
        return set()
    names = set()
    for f in ws.iterdir():
        if f.is_file() and f.suffix.lower() in DOCS and not f.name.startswith("."):
            src = inputs / f.name
            if not (src.exists() and src.read_bytes() == f.read_bytes()):
                names.add(f.name)
    return names


def render(src, out, dpi):
    out.mkdir(parents=True)
    if not src.exists():
        (out / "MISSING.txt").write_text("No such file was delivered.\n")
        return
    pdf = src
    if src.suffix.lower() != ".pdf":
        tmp = Path(tempfile.mkdtemp())
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", str(tmp), str(src)],
                       capture_output=True, timeout=180, check=False, env={"HOME": str(tmp), "PATH": "/usr/bin:/bin"})
        pdf = tmp / (src.stem + ".pdf")
    if not pdf.exists():
        (out / "MISSING.txt").write_text("LibreOffice could not open the file.\n")
        return
    subprocess.run(["pdftoppm", "-r", str(dpi), "-l", str(MAX_PAGES), "-png", str(pdf), str(out / "page")], check=True)
    subprocess.run(["pdftotext", "-layout", str(pdf), str(out / "text.txt")], check=True)
    if src.suffix.lower() == ".pptx":
        from pptx import Presentation
        notes = [f"Slide {i}: " + (s.notes_slide.notes_text_frame.text.strip() if s.has_notes_slide else "")
                 for i, s in enumerate(Presentation(src).slides, 1)]
        (out / "notes.txt").write_text("\n".join(notes) + "\n", encoding="utf-8")


def runs(results, task):
    """Pair numbers with both an a- and a b- run."""
    return sorted(int(d.name[2:]) for d in (results / task).glob("a-*") if (results / task / f"b-{d.name[2:]}").is_dir())


def blind(args):
    results, judge, tasks_dir = Path(args.results), Path(args.judge), Path(args.tasks)
    if (judge / "packets").exists():
        shutil.rmtree(judge / "packets")
    (judge / "packets").mkdir(parents=True)
    shutil.copy(tasks_dir / "JUDGE.md", judge / "JUDGE.md")
    key, batches = [], []
    tasks = sorted(d.name for d in results.iterdir() if d.is_dir() and (tasks_dir / d.name / "prompt.md").exists())
    for task in tasks:
        inputs = tasks_dir / task / "input"
        by_order = {1: [], 2: []}
        for n in runs(results, task):
            names = deliverables(results / task / f"a-{n}" / "ws", inputs) | deliverables(results / task / f"b-{n}" / "ws", inputs)
            first = random.randrange(2)
            for order in (1, 2):
                x = "a" if (first + order) % 2 == 0 else "b"
                y = "b" if x == "a" else "a"
                pid = secrets.token_hex(4)
                p = judge / "packets" / pid
                p.mkdir()
                shutil.copy(tasks_dir / task / "prompt.md", p / "task.md")
                shutil.copytree(inputs, p / "input")
                for label, side in (("X", x), ("Y", y)):
                    if not names:
                        render(Path("/nonexistent"), p / label / "deliverable", args.dpi)
                    for name in sorted(names):
                        render(results / task / f"{side}-{n}" / "ws" / name, p / label / name, args.dpi)
                key.append({"id": pid, "task": task, "pair": n, "order": order, "X": x})
                by_order[order].append(pid)
        for order in (1, 2):
            ids = by_order[order]
            random.shuffle(ids)
            for i in range(0, len(ids), args.batch):
                batches.append(" ".join(f"{args.host_judge}/packets/{pid}" for pid in ids[i:i + args.batch]))
    (results / "judge-key.json").write_text(json.dumps(key, indent=1))
    (judge / "batches.txt").write_text("\n".join(batches) + "\n")
    print(f"{len(key)} packets in {len(batches)} batches")


def verdicts(results, judge):
    """{task: {pair: {order: verdict in a/b terms}}} for every packet a judge has answered."""
    out = defaultdict(lambda: defaultdict(dict))
    for k in json.loads((results / "judge-key.json").read_text()):
        f = judge / "packets" / k["id"] / "verdict.json"
        if not f.exists():
            continue
        v = json.loads(f.read_text())
        side = {"X": k["X"], "Y": "b" if k["X"] == "a" else "a"}
        out[k["task"]][k["pair"]][k["order"]] = {
            "winner": side.get(v.get("preferred"), "tie"), "strength": v.get("strength", ""),
            "scores": {side[s]: v.get("scores", {}).get(s, {}) for s in ("X", "Y")},
            "reasons": v.get("reasons", ""), "id": k["id"], "X": k["X"]}
    return out


def summarize(pairs):
    both = {n: o for n, o in pairs.items() if 1 in o and 2 in o}
    final = {n: (o[1]["winner"] if o[1]["winner"] == o[2]["winner"] else "tie") for n, o in both.items()}
    means = {}
    for crit in CRITERIA:
        for s in "ab":
            vals = [o[k]["scores"][s].get(crit) for o in both.values() for k in (1, 2)]
            vals = [v for v in vals if isinstance(v, (int, float))]
            means[(crit, s)] = sum(vals) / len(vals) if vals else None
    return {"pairs": len(both), "consistent": sum(o[1]["winner"] == o[2]["winner"] for o in both.values()),
            "a": sum(w == "a" for w in final.values()), "b": sum(w == "b" for w in final.values()),
            "tie": sum(w == "tie" for w in final.values()), "means": means, "final": final, "both": both}


def graded(results):
    f = results / "results.json"
    rows = json.loads(f.read_text()) if f.exists() else []
    out = defaultdict(dict)
    for task in {r["task"] for r in rows}:
        for s in "ab":
            rs = [r for r in rows if r["task"] == task and r["side"] == s]
            if rs:
                out[task][s] = {"runs": len(rs), "score": sum(r["score"] for r in rs) / len(rs),
                                "all_pass": sum(r["score"] == 1 for r in rs),
                                "cost": sum(r["cost"] for r in rs) / len(rs),
                                "seconds": sum(r["seconds"] for r in rs) / len(rs),
                                "skill_runs": sum(bool(set(r["skills"]) - {"quality-assurance"}) for r in rs)}
    return out


def fmt(v, spec):
    return "–" if v is None else format(v, spec)


def examples(s, limit=3):
    """The clearest pairs: consistent verdicts first, the stronger first, both directions represented."""
    rank = {"strong": 3, "clear": 2, "slight": 1}
    order = sorted(s["both"], key=lambda n: (s["final"][n] == "tie",
                                             -sum(rank.get(s["both"][n][k]["strength"], 0) for k in (1, 2))))
    picked = []
    for want in ("a", "b", "tie"):
        picked += [n for n in order if s["final"][n] == want][:1]
    picked += [n for n in order if n not in picked]
    return picked[:limit]


def side_dirs(judge, o):
    """{a: dir, b: dir} of the X/Y renders in the order-1 packet."""
    p = judge / "packets" / o[1]["id"]
    return {o[1]["X"]: p / "X", ("b" if o[1]["X"] == "a" else "a"): p / "Y"}


def img(path):
    return f'<img alt="" src="data:image/png;base64,{base64.b64encode(path.read_bytes()).decode()}">'


def report(args):
    results, judge = Path(args.results), Path(args.judge)
    name = args.name or results.name
    settings = json.loads((results / "settings.json").read_text()) if (results / "settings.json").exists() else {}
    grades, per_task = graded(results), verdicts(results, judge)
    md = [f"# Blind judge: {name}", ""]
    if settings:
        md += [f"A `{settings.get('a')}` · B `{settings.get('b')}` · model `{settings.get('model')}`"
               f"{' (' + settings['variant'] + ')' if settings.get('variant') else ''}"
               f"{' · prompt suffix: ' + settings['prompt_suffix'] if settings.get('prompt_suffix') else ''}", ""]
    md += ["| task | pairs | same verdict both orders | A better | B better | tie |"
           + "".join(f" {c} A / B |" for c in CRITERIA),
           "| --- | --- | --- | --- | --- | --- |" + " --- |" * len(CRITERIA)]
    summaries = {t: summarize(p) for t, p in sorted(per_task.items())}
    for t, s in summaries.items():
        md.append(f"| {t} | {s['pairs']} | {s['consistent']}/{s['pairs']} | {s['a']} | {s['b']} | {s['tie']} |"
                  + "".join(f" {fmt(s['means'][(c, 'a')], '.1f')} / {fmt(s['means'][(c, 'b')], '.1f')} |" for c in CRITERIA))
    for t, s in summaries.items():
        md += ["", f"## {t}", ""]
        for n in sorted(s["both"]):
            o = s["both"][n]
            md.append(f"- pair {n}: **{s['final'][n].upper() if s['final'][n] != 'tie' else 'tie'}**"
                      f" ({o[1]['winner']} {o[1]['strength']}, {o[2]['winner']} {o[2]['strength']}): {o[1]['reasons']}")
    (results / "judge.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    e = html.escape
    parts = []
    for t, s in summaries.items():
        g = grades.get(t, {})
        rows = "".join(
            f"<tr><th>{label}</th>" + "".join(f"<td>{cell(g.get(side, {}))}</td>" for side in "ab") + "</tr>"
            for label, cell in (
                ("runs", lambda x: x.get("runs", "–")),
                ("checks passed", lambda x: fmt(x["score"] * 100, ".0f") + "%" if x else "–"),
                ("all checks passed", lambda x: x.get("all_pass", "–")),
                ("skill loaded", lambda x: x.get("skill_runs", "–")),
                ("cost per run", lambda x: "$" + fmt(x.get("cost"), ".4f") if x else "–"),
                ("time per run", lambda x: fmt(x.get("seconds"), ".0f") + " s" if x else "–")))
        crit = "".join(f"<tr><th>{c}</th><td>{fmt(s['means'][(c, 'a')], '.2f')}</td>"
                       f"<td>{fmt(s['means'][(c, 'b')], '.2f')}</td></tr>" for c in CRITERIA)
        verdict = (f"<p class=verdict><b>A better in {s['a']}</b>, <b>B better in {s['b']}</b>, tie in {s['tie']} "
                   f"of {s['pairs']} pairs · same verdict in both orders: {s['consistent']}/{s['pairs']}</p>")
        shows = []
        for n in examples(s):
            o = s["both"][n]
            dirs = side_dirs(judge, o)
            pages = []
            for doc in sorted({d.name for side in "ab" for d in dirs[side].iterdir() if d.is_dir()}):
                a_pages = sorted((dirs["a"] / doc).glob("page-*.png"))
                b_pages = sorted((dirs["b"] / doc).glob("page-*.png"))
                for i in range(max(len(a_pages), len(b_pages), 1)):
                    cells = []
                    for ps, side in ((a_pages, "a"), (b_pages, "b")):
                        missing = dirs[side] / doc / "MISSING.txt"
                        cells.append(f"<figure>{img(ps[i])}</figure>" if i < len(ps) else
                                     f"<figure class=empty>{e(missing.read_text().strip()) if missing.exists() else ''}</figure>")
                    pages.append(f"<div class=pair>{''.join(cells)}</div>")
            shows.append(f"<details><summary>Pair {n}: <b>{e(s['final'][n].upper() if s['final'][n] != 'tie' else 'tie')}</b>"
                         f" — {e(o[1]['reasons'])}</summary><div class=heads><span>A</span><span>B</span></div>"
                         f"{''.join(pages)}<p class=reason>Other order: {e(o[2]['reasons'])}</p></details>")
        parts.append(f"<section><h2>{e(t)}</h2>{verdict}<div class=tables><table><caption>Graded checks</caption>"
                     f"<tr><th></th><th>A</th><th>B</th></tr>{rows}</table><table><caption>Judge scores (1–5)</caption>"
                     f"<tr><th></th><th>A</th><th>B</th></tr>{crit}</table></div>{''.join(shows)}</section>")
    head = (f"A <code>{e(str(settings.get('a', '?')))}</code> · B <code>{e(str(settings.get('b', '?')))}</code> · "
            f"model <code>{e(str(settings.get('model', '?')))}</code>"
            + (f" ({e(settings['variant'])})" if settings.get("variant") else "")
            + (f"<br>Prompt suffix: {e(settings['prompt_suffix'])}" if settings.get("prompt_suffix") else ""))
    page = f"""<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>A/B Judge Report</title>
<style>
:root{{--bg:#fafaf9;--fg:#1c1917;--muted:#57534e;--line:#d6d3d1;--card:#fff;--accent:#3f7a57}}
@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#1c1917;--fg:#f5f5f4;--muted:#a8a29e;--line:#44403c;--card:#292524;--accent:#6fb58a}}}}
:root[data-theme=dark]{{--bg:#1c1917;--fg:#f5f5f4;--muted:#a8a29e;--line:#44403c;--card:#292524;--accent:#6fb58a}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}}
main{{max-width:1100px;margin:0 auto;padding:24px 16px}}
h1{{font-size:1.5rem;margin:0 0 4px}} h2{{font-size:1.2rem;margin:0 0 8px}}
.meta,.reason,caption{{color:var(--muted)}} code{{font-size:.9em}}
section{{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:16px;margin:16px 0}}
.verdict b{{color:var(--accent)}} .tables{{display:flex;flex-wrap:wrap;gap:24px;margin:8px 0}}
table{{border-collapse:collapse}} th,td{{padding:2px 10px;text-align:left;border-bottom:1px solid var(--line)}}
caption{{text-align:left;font-size:.85rem}}
details{{border-top:1px solid var(--line);padding:8px 0}} summary{{cursor:pointer}}
.heads,.pair{{display:grid;grid-template-columns:1fr 1fr;gap:12px}} .heads{{font-weight:600;margin:8px 0 4px}}
figure{{margin:0 0 12px}} figure img{{max-width:100%;height:auto;border:1px solid var(--line);background:#fff}}
figure.empty{{color:var(--muted);font-style:italic}}
</style></head><body><main><h1>A/B judge report: {e(name)}</h1><p class=meta>{head}</p>
<p class=meta>Each pair of runs was judged blind, twice with the order swapped; a pair counts for a side only when
both orders agree. The graded checks are the task's own grader. Open a pair to see both deliverables page by page.</p>
{''.join(parts)}</main></body></html>"""
    (results / "report.html").write_text(page, encoding="utf-8")
    print((results / "judge.md").read_text())


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("blind")
    b.add_argument("results")
    b.add_argument("judge")
    b.add_argument("tasks")
    b.add_argument("host_judge")
    b.add_argument("--batch", type=int, default=5)
    b.add_argument("--dpi", type=int, default=60)
    r = sub.add_parser("report")
    r.add_argument("results")
    r.add_argument("judge")
    r.add_argument("--name", default="")
    args = ap.parse_args()
    {"blind": blind, "report": report}[args.cmd](args)


main()
