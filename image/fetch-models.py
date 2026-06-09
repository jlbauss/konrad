#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Fetch the Docling model set into /opt/models at pinned, reproducible revisions.

Runs at image-build time in the `python-models` stage (which carries the full
venv, hence docling + torch). It reuses docling's *own* per-model download logic
rather than re-implementing it — so rapidocr's hardcoded URL matrix and the HF
snapshot layout stay docling's concern; we only inject the pinned revisions that
docling otherwise leaves floating at `main`.

Why pin at all: docling resolves layout / code-formula / picture-classifier at
`revision="main"`, so an unpinned rebuild silently pulls whatever main points to
that day. The model layer's bytes drift and every user re-pulls ~1.1 GB even when
the models they actually use didn't change. Pinning those three to a sha from
image/locks/models.lock (bot-maintained, like every other lock) makes the layer
byte-stable across rebuilds — combined with the CI rewrite-timestamp pass, that's
what lets users skip the re-download. Tableformer is already tag-pinned by docling
(v2.3.0) and rapidocr is a fixed file set tied to the locked docling-slim version,
so both stay on docling's defaults and are not listed in the lock.

Folder layout: each model lands in OUT/<repo_id with '/' -> '--'> (docling's
convention), and the runtime resolves them via DOCLING_ARTIFACTS_PATH=/opt/models.
"""

import sys
from pathlib import Path

from docling.models.stages.ocr.rapid_ocr_model import RapidOcrModel
from docling.models.stages.table_structure.table_structure_model import (
    TableStructureModel,
)
from docling.models.utils.hf_model_download import download_hf_model

OUT = Path("/opt/models")


def read_lock(path):
    """Parse `<repo_id> <sha>` lines, skipping blanks and `#` comments."""
    pins = {}
    for raw in path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        repo, sha = line.split()
        pins[repo] = sha
    return pins


def main():
    pins = read_lock(Path(sys.argv[1]))
    if not pins:
        sys.exit("models.lock has no entries")

    # main-tracked HF snapshots, pinned by sha from the lock.
    for repo, sha in pins.items():
        print(f"fetch {repo}@{sha}", flush=True)
        download_hf_model(
            repo_id=repo, revision=sha, local_dir=OUT / repo.replace("/", "--")
        )

    # Tableformer: docling tag-pins this internally (v2.3.0) — use its downloader.
    print("fetch tableformer (docling-pinned)", flush=True)
    TableStructureModel.download_models(
        local_dir=OUT / TableStructureModel._model_repo_folder
    )

    # RapidOCR: not a repo snapshot — docling fetches a fixed per-backend/language
    # file set (pinned implicitly by the locked docling-slim version). Mirror the
    # default download orchestrator's matrix.
    for backend in ("torch", "onnxruntime"):
        for lang in ("chinese", "english"):
            print(f"fetch rapidocr {backend}/{lang}", flush=True)
            RapidOcrModel.download_models(
                backend=backend,
                local_dir=OUT / RapidOcrModel._model_repo_folder,
                lang=lang,
            )


if __name__ == "__main__":
    main()
