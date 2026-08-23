#!/usr/bin/env python3
"""The mechanical half of a documentation resync.

Everything here is deterministic: a link resolves or it does not, an ID is unique
or it is not. Judgement — whether a spec still describes what the module does,
whether an ADR's consequences are still true — is the agent's half and is not
attempted. See SKILL.md beside this file.

Run from the repository root. Exits 1 if anything is reported.
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))

# `.claude/` holds worktrees, which are whole copies of this repository — walking
# them reports every finding a second time, attributed to a path that is not the
# working tree. `charts/` is a vendored upstream chart, unpacked and not ours.
SKIP = {".git", ".claude", ".terraform", ".ci-out", "charts",
        ".tofu-plugin-cache", "node_modules"}

findings = []


def report(path, message):
    findings.append((os.path.relpath(path, ROOT), message))


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def markdown_files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP]
        for name in sorted(names):
            if name.endswith(".md"):
                yield os.path.join(base, name)


# ---------------------------------------------------------------- anchors

FENCE = re.compile(r"^\s*```")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
INLINE_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")


def slug(text):
    """GitHub's heading slug: strip markdown, lowercase, punctuation out, spaces to hyphens."""
    text = INLINE_LINK.sub(r"\1", text)
    text = text.replace("`", "").replace("*", "")
    text = "".join(c for c in text.lower() if c.isalnum() or c in " -_")
    return "-".join(text.split())


def headings(path):
    """Every heading in a file, in order, as (level, raw text)."""
    out, in_fence = [], False
    for line in read(path).splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING.match(line)
        if match:
            out.append((len(match.group(1)), match.group(2)))
    return out


def anchors(path):
    """The set of anchors a file offers, including GitHub's -1/-2 disambiguators."""
    seen, offered = defaultdict(int), set()
    for _, text in headings(path):
        base = slug(text)
        if not base:
            continue
        offered.add(base if seen[base] == 0 else "%s-%d" % (base, seen[base]))
        seen[base] += 1
    return offered


ANCHOR_CACHE = {}


def anchors_cached(path):
    if path not in ANCHOR_CACHE:
        ANCHOR_CACHE[path] = anchors(path)
    return ANCHOR_CACHE[path]


def check_duplicate_headings(path):
    """Two headings with one name make every link to either of them a coin toss."""
    seen = defaultdict(list)
    for level, text in headings(path):
        if level > 1:
            seen[slug(text)].append(text)
    for key, texts in sorted(seen.items()):
        if len(texts) > 1 and key:
            report(path, "heading '%s' appears %d times — a link to #%s reaches "
                         "whichever came first" % (texts[0], len(texts), key))


# ------------------------------------------------------------------ links

LINK = re.compile(r"\[[^\]]*\]\(\s*<?([^)\s>]+)>?[^)]*\)")


def check_links(path):
    for target in LINK.findall(read(path)):
        if target.startswith(("http://", "https://", "mailto:", "tel:")):
            continue
        file_part, _, anchor = target.partition("#")
        if file_part:
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), file_part))
            if not os.path.exists(resolved):
                report(path, "link to '%s' resolves to nothing" % target)
                continue
        else:
            resolved = path
        if anchor and resolved.endswith(".md"):
            if anchor not in anchors_cached(resolved):
                report(path, "link to '%s' names an anchor that file does not offer" % target)


# ---------------------------------------------------------------- indexes

def module_dirs():
    base = os.path.join(ROOT, "docs", "modules")
    if not os.path.isdir(base):
        return []
    return sorted(d for d in os.listdir(base)
                  if os.path.isdir(os.path.join(base, d)))


def check_spec_index():
    """Every spec is listed where specs are listed, and every listing has a spec."""
    index = read(os.path.join(ROOT, "docs", "README.md"))
    for module in module_dirs():
        spec = os.path.join(ROOT, "docs", "modules", module, "README.md")
        if not os.path.exists(spec):
            report(spec, "module folder exists with no spec in it")
            continue
        if "modules/%s/README.md" % module not in index:
            report(os.path.join(ROOT, "docs", "README.md"),
                   "spec '%s' is not in the specifications index" % module)
    for referenced in set(re.findall(r"modules/([a-z0-9-]+)/README\.md", index)):
        if referenced not in module_dirs():
            report(os.path.join(ROOT, "docs", "README.md"),
                   "index lists '%s', which has no spec folder" % referenced)


def check_adr_index():
    """Every decision file is in a decisions table, and every row has a file."""
    index = read(os.path.join(ROOT, "docs", "README.md"))
    on_disk = []
    adr_dir = os.path.join(ROOT, "docs", "adr")
    if os.path.isdir(adr_dir):
        on_disk += [("adr/" + n) for n in sorted(os.listdir(adr_dir)) if n.endswith(".md")]
    for module in module_dirs():
        folder = os.path.join(ROOT, "docs", "modules", module, "adr")
        if os.path.isdir(folder):
            on_disk += ["modules/%s/adr/%s" % (module, n)
                        for n in sorted(os.listdir(folder)) if n.endswith(".md")]
    for relative in on_disk:
        if "(%s)" % relative not in index:
            report(os.path.join(ROOT, "docs", "README.md"),
                   "decision '%s' exists on disk and is in no decisions table" % relative)


def check_module_is_mentioned():
    """A module nobody mentions, or a mention of one that is gone, is the shape
    a removal leaves behind — it was two leftovers like this that survived the
    first pass at removing a module."""
    for where in ("README.md", os.path.join("docs", "platform.md")):
        path = os.path.join(ROOT, where)
        body = read(path)
        for module in module_dirs():
            if module not in body:
                report(path, "module '%s' is not mentioned here" % module)


# ---------------------------------------------------------- specs vs code

STATUS = re.compile(r"^\*\*Status:\*\*\s*([a-z ]+?)\s*(?:·|$)", re.MULTILINE)


def check_spec_status():
    """`draft` means nothing implements it; `implemented` means something does.
    A spec left at draft while its module runs is the drift the field exists for."""
    for module in module_dirs():
        spec = os.path.join(ROOT, "docs", "modules", module, "README.md")
        if not os.path.exists(spec):
            continue
        match = STATUS.search(read(spec))
        if not match:
            report(spec, "no **Status:** in the header")
            continue
        status = match.group(1)
        built = os.path.isdir(os.path.join(ROOT, "modules", module))
        if status not in ("draft", "implemented"):
            report(spec, "status '%s' is not a spec status — a spec is draft or "
                         "implemented, and is never accepted" % status)
        elif built and status != "implemented":
            report(spec, "status is '%s' but modules/%s/ exists" % (status, module))
        elif not built and status == "implemented":
            report(spec, "status is 'implemented' but there is no modules/%s/" % module)


def check_charts_are_at_the_root():
    """A chart is something this repository publishes, so it lives in helm/ and not inside the
    one module that happens to render it today."""
    base = os.path.join(ROOT, "modules")
    for where, _, names in os.walk(base):
        if "Chart.yaml" in names and "/charts/" not in where.replace(os.sep, "/"):
            report(os.path.join(where, "Chart.yaml"),
                   "a chart under modules/ — charts belong at helm/<chart>/")
    charts = os.path.join(ROOT, "helm")
    if not os.path.isdir(charts):
        return
    for name in sorted(os.listdir(charts)):
        chart = os.path.join(charts, name)
        if not os.path.isdir(chart):
            continue
        if not os.path.exists(os.path.join(chart, "Chart.yaml")):
            report(chart, "directory in helm/ with no Chart.yaml")
        elif not glob_ci(chart):
            report(chart, "no ci/*.yaml — helm-lint and helm-template loop over them under "
                          "`set -e`, so this fails the build rather than being skipped")


def glob_ci(chart):
    folder = os.path.join(chart, "ci")
    if not os.path.isdir(folder):
        return []
    return [n for n in os.listdir(folder) if n.endswith((".yaml", ".yml"))]


def check_module_has_spec():
    """Code with no spec is §10.2 in reverse."""
    base = os.path.join(ROOT, "modules")
    if not os.path.isdir(base):
        return
    for name in sorted(os.listdir(base)):
        if not os.path.isdir(os.path.join(base, name)) or name == "secret-template":
            continue
        if not os.path.exists(os.path.join(ROOT, "docs", "modules", name, "README.md")):
            report(os.path.join(base, name), "module has no spec in docs/modules/")


# ---------------------------------------------------------------- adr shape

ADR_SECTIONS = ["Decision", "Context", "Rationale", "Alternatives", "Consequences"]

# ADR 006 is a tombstone: its decision moved into 007 and the file survives to record where it
# went. A pointer does not need the four sections, and docs/README.md says so.
ADR_SHAPE_EXEMPT = {"006-shared-gateway-input.md"}


def adr_files():
    base = os.path.join(ROOT, "docs", "adr")
    if os.path.isdir(base):
        for name in sorted(os.listdir(base)):
            if name.endswith(".md"):
                yield os.path.join(base, name)
    for module in module_dirs():
        folder = os.path.join(ROOT, "docs", "modules", module, "adr")
        if os.path.isdir(folder):
            for name in sorted(os.listdir(folder)):
                if name.endswith(".md"):
                    yield os.path.join(folder, name)


def check_adr_shape():
    """Decision first, then Context, Rationale, Alternatives, Consequences — and a lede above
    them. The order is the inverted pyramid: a reader after *what* stops before *why*."""
    for path in adr_files():
        if os.path.basename(path) in ADR_SHAPE_EXEMPT:
            continue
        found = [text for level, text in headings(path) if level == 2]
        if found != ADR_SECTIONS:
            report(path, "sections are %s — expected %s"
                   % (" → ".join(found) or "none", " → ".join(ADR_SECTIONS)))
        # The lede is a paragraph, not a line: it wraps like everything else here.
        paragraphs = read(path).split("\n## ")[0].split("\n\n")
        lede = [p for p in paragraphs
                if p.strip().startswith("**") and p.strip().endswith("**")
                and "Status:" not in p]
        if not lede:
            report(path, "no lede — one bold sentence under the header saying what was decided")


# ------------------------------------------------------------- scenario ids

SCENARIO = re.compile(r"Scenario(?: Outline)?:\s*\[([A-Z]{2,8}-\d{2})\]")
CITATION = re.compile(r"\b([A-Z]{2,8}-\d{2})\b")


def check_scenario_ids():
    defined = {}
    for module in module_dirs():
        spec = os.path.join(ROOT, "docs", "modules", module, "README.md")
        if not os.path.exists(spec):
            continue
        for scenario_id in SCENARIO.findall(read(spec)):
            if scenario_id in defined:
                report(spec, "scenario %s is also defined in %s — an ID names one "
                             "scenario and is never reused" % (scenario_id, defined[scenario_id]))
            defined[scenario_id] = module
    for path in (os.path.join(ROOT, "docs", "platform.md"),):
        for scenario_id in SCENARIO.findall(read(path)):
            if scenario_id in defined:
                report(path, "scenario %s is also defined in %s"
                       % (scenario_id, defined[scenario_id]))
            defined[scenario_id] = "platform"

    requirements = os.path.join(ROOT, "docs", "requirements.md")
    for cited in sorted(set(CITATION.findall(read(requirements)))):
        if cited.startswith(("REQ-", "ADR-", "LOCAL-")):
            continue
        if cited not in defined:
            report(requirements, "the matrix cites %s, which no spec defines" % cited)


# ------------------------------------------------------- code cites nothing

CODE_CITES = re.compile(r"(?:\bADR[ -]\d|\bREQ-\d{2}\b|\bLOCAL-\d{3}\b|§\d)")


def code_files():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP | {".agents", "docs"}]
        for name in sorted(names):
            if name.endswith((".tf", ".tpl", ".yaml", ".yml")):
                yield os.path.join(base, name)


def check_code_cites_no_document():
    """Traceability runs documentation to code and never back: a citation in a
    comment is a link nothing checks, in a repository that renumbers."""
    for path in code_files():
        for number, line in enumerate(read(path).splitlines(), start=1):
            if CODE_CITES.search(line):
                report(path, "line %d cites a document — state the reason itself "
                             "instead: %s" % (number, line.strip()[:70]))


# -------------------------------------------------------------------- main

def main():
    for path in markdown_files():
        check_links(path)
        check_duplicate_headings(path)
    check_spec_index()
    check_adr_index()
    check_adr_shape()
    check_module_is_mentioned()
    check_spec_status()
    check_module_has_spec()
    check_charts_are_at_the_root()
    check_scenario_ids()
    check_code_cites_no_document()

    if not findings:
        print("docs: nothing to report")
        return 0
    by_file = defaultdict(list)
    for path, message in findings:
        by_file[path].append(message)
    for path in sorted(by_file):
        print("==> %s" % path)
        for message in by_file[path]:
            print("    %s" % message)
    print("\n%d finding(s)" % len(findings))
    return 1


if __name__ == "__main__":
    sys.exit(main())
