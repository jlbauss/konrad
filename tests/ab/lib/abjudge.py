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
import re
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

from abdump import outline

DOCS = {".docx", ".pptx", ".xlsx", ".pdf"}
TEXTS = {".txt", ".csv", ".md", ".json"}
CRITERIA = ("request", "fidelity", "presentation")
MAX_PAGES = 12


def deliverables(ws, inputs):
    """Office files, PDFs and text files the run left in its workspace, other than unchanged inputs."""
    if not ws.is_dir():
        return set()
    names = set()
    for f in ws.iterdir():
        if f.is_file() and f.suffix.lower() in DOCS | TEXTS and not f.name.startswith("."):
            src = inputs / f.name
            if not (src.exists() and src.read_bytes() == f.read_bytes()):
                names.add(f.name)
    return names


def render(src, out, dpi):
    out.mkdir(parents=True)
    if not src.exists():
        (out / "MISSING.txt").write_text("No such file was delivered.\n")
        return
    if src.suffix.lower() in TEXTS:
        shutil.copy(src, out / "text.txt")
        return
    try:
        shape = outline(src)
    except Exception as exc:  # noqa: BLE001 — a file its library can't read is itself a finding
        shape = {"error": f"could not read the file's structure: {type(exc).__name__}"}
    if shape is not None:
        (out / "outline.json").write_text(json.dumps(shape, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
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
    results, judge, tasks_dir = Path(args.results), Path(args.judge), Path(args.tasks_dir)
    if (judge / "packets").exists():
        shutil.rmtree(judge / "packets")
    (judge / "packets").mkdir(parents=True)
    shutil.copy(tasks_dir / "JUDGE.md", judge / "JUDGE.md")
    key, batches = [], []
    tasks = sorted(d.name for d in results.iterdir() if d.is_dir() and (tasks_dir / d.name / "prompt.md").exists())
    if args.tasks:
        tasks = [t for t in tasks if t in args.tasks.split(",")]
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
                for f in sorted(inputs.iterdir()):
                    if f.suffix.lower() in DOCS:
                        render(f, p / "input" / f.name, args.dpi)
                    else:
                        (p / "input").mkdir(exist_ok=True)
                        shutil.copy(f, p / "input" / f.name)
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
    """Per task and side: the automatic checks, time, cost and tokens of the runs."""
    f = results / "results.json"
    rows = json.loads(f.read_text()) if f.exists() else []
    out = defaultdict(dict)
    for task in {r["task"] for r in rows}:
        for s in "ab":
            rs = [r for r in rows if r["task"] == task and r["side"] == s]
            if rs:
                def mean(k):
                    return sum(r.get(k) or 0 for r in rs) / len(rs)
                out[task][s] = {"runs": len(rs), "score": mean("score"),
                                "all_pass": sum(r["score"] == 1 for r in rs),
                                "cost": mean("cost"), "seconds": mean("seconds"),
                                "tokens_in": mean("tokens_in"), "tokens_out": mean("tokens_out"),
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
    return f'<img alt="" loading="lazy" src="data:image/png;base64,{base64.b64encode(path.read_bytes()).decode()}">'


def ab_terms(text, x):
    """A reviewer's reasons with X and Y replaced by the versions they stood for."""
    y = "b" if x == "a" else "a"
    return re.sub(r"\b([XY])\b", lambda m: (x if m.group(1) == "X" else y).upper(), text)


def call(s):
    """How a task came out, in one phrase, and who won ('a', 'b' or '')."""
    a, b, n = s["a"], s["b"], s["pairs"] or 1
    if a == b or abs(a - b) < 2:
        return "no real difference", ""
    lead, win = ("A", "a") if a > b else ("B", "b")
    return (f"{lead} clearly better" if abs(a - b) >= n / 2 else f"{lead} somewhat better"), win


def first_sentence(text):
    m = re.match(r"(.+?[.!?])(\s|$)", text.strip().replace("\n", " "))
    return m.group(1) if m else text.strip()[:200]


def report(args):
    results, judge, tasks_dir = Path(args.results), Path(args.judge), Path(args.tasks_dir)
    name = args.name or results.name
    settings = json.loads((results / "settings.json").read_text()) if (results / "settings.json").exists() else {}
    label = {"a": args.a_label or settings.get("a", "A"), "b": args.b_label or settings.get("b", "B")}
    image = {"a": settings.get("a", "?"), "b": settings.get("b", "?")}
    model = settings.get("model", "?") + (f" ({settings['variant']} effort)" if settings.get("variant") else "")
    question = args.question or "Does version B produce better results than version A?"
    grades, per_task = graded(results), verdicts(results, judge)
    summaries = {t: summarize(p) for t, p in sorted(per_task.items())}
    calls = {t: call(s) for t, s in summaries.items()}
    runs_n = settings.get("runs") or max((g.get("a", {}).get("runs", 0) for g in grades.values()), default=0)
    wins = {w: [t for t, (_, cw) in calls.items() if cw == w] for w in ("a", "b", "")}
    agree = sum(s["consistent"] for s in summaries.values()), sum(s["pairs"] for s in summaries.values())
    answer = (f"Of {len(summaries)} tasks, A was better in {len(wins['a'])}, B in {len(wins['b'])}, "
              f"and {len(wins[''])} showed no real difference.")
    prompts = {t: first_sentence((tasks_dir / t / "prompt.md").read_text()) if (tasks_dir / t / "prompt.md").exists() else ""
               for t in summaries}

    # judge.md: the short version, for the MR description.
    md = [f"**{question}** {answer}", "",
          f"A = {label['a']} (`{image['a']}`), B = {label['b']} (`{image['b']}`); {runs_n} runs each per task with "
          f"`{model}`; every pair reviewed blind, twice with the order swapped"
          + (f", by {args.judge_label}" if args.judge_label else "") + ".", "",
          "| task | outcome | pairs: A better / tie / B better | reviews agreed | checks passed A / B | tokens read A / B (k) |",
          "| --- | --- | --- | --- | --- | --- |"]
    for t, s in summaries.items():
        g = grades.get(t, {})
        md.append(f"| {t} | {calls[t][0]} | {s['a']} / {s['tie']} / {s['b']} | {s['consistent']}/{s['pairs']} | "
                  f"{fmt(g.get('a', {}).get('score', 0) * 100, '.0f')}% / {fmt(g.get('b', {}).get('score', 0) * 100, '.0f')}% | "
                  f"{fmt(g.get('a', {}).get('tokens_in', 0) / 1000, '.0f')} / {fmt(g.get('b', {}).get('tokens_in', 0) / 1000, '.0f')} |")
    (results / "judge.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    e = html.escape
    sections = []
    for t, s in summaries.items():
        g = grades.get(t, {})
        verdict, winner = calls[t]
        n = s["pairs"] or 1
        bar = "".join(f'<span class="seg {k}" style="width:{100 * s[k] / n:.1f}%">{s[k] if s[k] else ""}</span>'
                      for k in ("a", "tie", "b"))

        def row(title, f, digits=None):
            cells = "".join(f"<td>{f(g[side]) if side in g else '–'}</td>" for side in "ab")
            return f"<tr><th>{title}</th>{cells}</tr>"
        rows = "".join([
            row("automatic checks passed", lambda x: f"{x['score'] * 100:.0f}% ({x['all_pass']} of {x['runs']} runs flawless)"),
            *(f"<tr><th>review score: {c}</th><td>{fmt(s['means'][(c, 'a')], '.1f')} / 5</td>"
              f"<td>{fmt(s['means'][(c, 'b')], '.1f')} / 5</td></tr>" for c in CRITERIA),
            row("time per run", lambda x: f"{x['seconds']:.0f} s"),
            row("tokens read / written per run", lambda x: f"{x['tokens_in'] / 1000:.0f}k / {x['tokens_out'] / 1000:.1f}k"),
            row("cost per run", lambda x: f"${x['cost']:.4f}"),
            row("runs that used a skill", lambda x: f"{x['skill_runs']} of {x['runs']}"),
        ])
        quotes = []
        for n_ in examples(s):
            o = s["both"][n_]
            dirs = side_dirs(judge, o)
            pages = []
            for doc in sorted({d.name for side in "ab" for d in dirs[side].iterdir() if d.is_dir()}):
                a_pages = sorted((dirs["a"] / doc).glob("page-*.png"))
                b_pages = sorted((dirs["b"] / doc).glob("page-*.png"))
                for i in range(max(len(a_pages), len(b_pages))):
                    cells = []
                    for ps, side in ((a_pages, "a"), (b_pages, "b")):
                        missing = dirs[side] / doc / "MISSING.txt"
                        cells.append(f"<figure>{img(ps[i])}</figure>" if i < len(ps) else
                                     f"<figure class=empty>{e(missing.read_text().strip()) if missing.exists() and i == 0 else ''}</figure>")
                    pages.append(f"<div class=pair>{''.join(cells)}</div>")
            outcome = {"a": "A better", "b": "B better", "tie": "no difference"}[s["final"][n_]]
            quotes.append(
                f"<details><summary><b>Run {n_}: {outcome}.</b> {e(ab_terms(o[1]['reasons'], o[1]['X']))}</summary>"
                f"<p class=muted>Second review, order swapped: {e(ab_terms(o[2]['reasons'], o[2]['X']))}</p>"
                + (f"<div class=heads><span>A</span><span>B</span></div>{''.join(pages)}" if pages else "")
                + "</details>")
        sections.append(f"""<section class=task><h3>{e(t)}</h3>
<p class=prompt>“{e(prompts[t])}”</p>
<p class="call {winner or 'none'}">{e(verdict[0].upper() + verdict[1:])}</p>
<div class=bar role=img aria-label="{s['a']} pairs A better, {s['tie']} no difference, {s['b']} B better">{bar}</div>
<p class="legend muted"><span class="key a"></span>A better: {s['a']} <span class="key tie"></span>no difference: {s['tie']}
<span class="key b"></span>B better: {s['b']} · the two reviews of a pair agreed in {s['consistent']} of {s['pairs']}</p>
<table><tr><th></th><th>A</th><th>B</th></tr>{rows}</table>
<h4>Why: the reviewers’ reasons, with the results side by side</h4>{''.join(quotes)}</section>""")

    task_list = "".join(f"<li><b>{e(t)}</b>: “{e(prompts[t])}”</li>" for t in summaries)
    page = f"""<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>A/B Test Report</title>
<style>
:root{{--bg:#fafaf9;--fg:#1c1917;--muted:#57534e;--line:#d6d3d1;--card:#fff;--a:#2563eb;--b:#c2410c;--tie:#a8a29e}}
@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#1c1917;--fg:#f5f5f4;--muted:#a8a29e;--line:#44403c;--card:#292524;--a:#60a5fa;--b:#fb923c;--tie:#78716c}}}}
:root[data-theme=dark]{{--bg:#1c1917;--fg:#f5f5f4;--muted:#a8a29e;--line:#44403c;--card:#292524;--a:#60a5fa;--b:#fb923c;--tie:#78716c}}
body{{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,sans-serif}}
main{{max-width:960px;margin:0 auto;padding:28px 16px 64px}}
h1{{font-size:1.6rem;line-height:1.25;margin:0 0 6px}} h2{{font-size:1.2rem;margin:36px 0 8px}} h3{{margin:0 0 4px}} h4{{margin:20px 0 6px;font-size:1rem}}
.lead{{font-size:1.15rem}} .muted,.prompt{{color:var(--muted)}} .prompt{{font-style:italic;margin:0 0 10px}}
.abstract{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 18px}}
.task{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:18px;margin:16px 0}}
.call{{font-size:1.15rem;font-weight:650;margin:0 0 8px}} .call.a{{color:var(--a)}} .call.b{{color:var(--b)}}
.bar{{display:flex;height:26px;border-radius:6px;overflow:hidden;background:var(--line)}}
.seg{{display:flex;align-items:center;justify-content:center;color:#fff;font-size:.85rem;font-weight:600;min-width:0}}
.seg.a,.key.a{{background:var(--a)}} .seg.b,.key.b{{background:var(--b)}} .seg.tie,.key.tie{{background:var(--tie)}}
.legend{{font-size:.85rem;margin:6px 0 12px}} .key{{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 4px 0 10px}}
.legend .key:first-child{{margin-left:0}}
table{{border-collapse:collapse;width:100%;font-size:.92rem}} th,td{{padding:4px 8px;text-align:left;border-bottom:1px solid var(--line)}}
th{{font-weight:500;color:var(--muted)}} tr:first-child th{{color:var(--fg);font-weight:650}}
details{{border-top:1px solid var(--line);padding:8px 0}} summary{{cursor:pointer}}
.heads,.pair{{display:grid;grid-template-columns:1fr 1fr;gap:12px}} .heads{{font-weight:650;margin:10px 0 4px}}
figure{{margin:0 0 12px}} figure img{{max-width:100%;height:auto;border:1px solid var(--line);background:#fff}}
figure.empty{{color:var(--muted);font-style:italic}}
ol li,ul li{{margin:4px 0}} code{{font-size:.9em}}
</style></head><body><main>
<p class=muted>A/B test report · {e(name)}</p>
<h1>{e(question)}</h1>
<p class=lead>{e(answer)}</p>

<div class=abstract><b>In short.</b> Two versions of konrad, A ({e(label['a'])}) and B ({e(label['b'])}), did the same
{len(summaries)} tasks, {runs_n} times each, with the same AI model. Every result was checked automatically for hard facts
(is the old name gone, is the chart there), and every pair of results was compared by independent AI reviewers who
didn’t know which version made which. {e(answer)}</div>

<h2>What was compared</h2>
<table><tr><th></th><th>A</th><th>B</th></tr>
<tr><th>version</th><td>{e(label['a'])}</td><td>{e(label['b'])}</td></tr>
<tr><th>image</th><td><code>{e(image['a'])}</code></td><td><code>{e(image['b'])}</code></td></tr></table>
<p>Both versions ran with <code>{e(model)}</code>{(' and this added to each request: “' + e(settings['prompt_suffix']) + '”') if settings.get('prompt_suffix') else ''}.
The tasks:</p><ul>{task_list}</ul>

<h2>How</h2>
<ol>
<li><b>Same task, same input, {runs_n} runs per version.</b> Run 1 of A and run 1 of B form a <i>pair</i>, and so on:
{runs_n} pairs per task.</li>
<li><b>Automatic checks.</b> Each task has a small test that checks fixed facts about the result. They tell whether a
result is correct, not whether it is good.</li>
<li><b>Blind review.</b> An AI reviewer{(' (' + e(args.judge_label) + ')') if args.judge_label else ''} gets the request,
the input and both results as page images and text, labelled only “X” and “Y” in random order. It scores both on
<i>request</i> (did it do what was asked), <i>fidelity</i> (is the data right) and <i>presentation</i> (could you hand
it on as it is), and says which it would rather receive, or that it makes no difference.</li>
<li><b>Each pair is reviewed twice,</b> by different reviewers, with X and Y swapped. A pair counts as a win only if
both reviews pick the same version; otherwise it counts as no difference. How often the two reviews agree shows how
reliable the reviewing is.</li>
<li><b>A task’s outcome</b> is “clearly better” when one version wins at least half of all pairs more than the
other, “somewhat better” when it wins at least two more, and “no real difference” otherwise. Time, tokens and cost
come from the runs themselves.</li>
</ol>

<h2>Results</h2>
<p class=muted>The two reviews of a pair agreed in {agree[0]} of {agree[1]} pairs overall.</p>
{''.join(sections)}

<h2>Limits</h2>
<ul>
<li>{runs_n} pairs per task show clear differences, not subtle ones.</li>
<li>The reviewers are AI models. They agreed with themselves as shown above, but nobody checked every verdict by hand.</li>
<li>The runs used <code>{e(model)}</code>; another model, such as the local one konrad is tuned for, may behave differently.</li>
<li>The reviewers are kept blind by instruction: they could have looked at other files on disk.</li>
</ul>
</main></body></html>"""
    (results / "report.html").write_text(page, encoding="utf-8")
    print((results / "judge.md").read_text())


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("blind")
    b.add_argument("results")
    b.add_argument("judge")
    b.add_argument("tasks_dir")
    b.add_argument("host_judge")
    b.add_argument("--batch", type=int, default=5)
    b.add_argument("--dpi", type=int, default=60)
    b.add_argument("--tasks", default="", help="comma-separated; default all tasks in the results dir")
    r = sub.add_parser("report")
    r.add_argument("results")
    r.add_argument("judge")
    r.add_argument("--name", default="")
    r.add_argument("--tasks-dir", dest="tasks_dir", default="/ab")
    r.add_argument("--question", default="")
    r.add_argument("--a-label", dest="a_label", default="")
    r.add_argument("--b-label", dest="b_label", default="")
    r.add_argument("--judge-label", dest="judge_label", default="")
    args = ap.parse_args()
    {"blind": blind, "report": report}[args.cmd](args)


main()
