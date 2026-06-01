# Top-level Python deps for the konrad runtime venv. This is the input to
# `uv pip compile`; the resolved output lives alongside in python.lock.
# Bump by hand only when adding/removing a top-level dep — the daily
# resolve-locks CI job re-resolves transitive pins automatically.
docling-slim[standard]
openpyxl
pandas
pypdf
pdfplumber
pdf2image
reportlab
onnxruntime
pillow-heif
