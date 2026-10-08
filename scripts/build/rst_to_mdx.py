#!/usr/bin/env python3
"""Convert the Sphinx RST lab guide into Mintlify MDX.

Walks Sphinx's *resolved* doctrees (so ``literalinclude`` is already inlined and
cross-references are resolved), then emits one ``.mdx`` file per doc under
``mint/`` with YAML frontmatter and Mintlify callouts. Sphinx stays the source
of truth; this regenerates the Mintlify mirror.

Usage:  python scripts/build/rst_to_mdx.py
Run from the repo root. Requires sphinx + sphinx_rtd_theme.
"""
import os
import re
import sys

from docutils import nodes
from sphinx.application import Sphinx

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRCDIR = os.path.join(REPO, "docs")
OUTDIR = os.path.join(REPO, "mint")

# docname (as Sphinx sees it) -> published mint path (no extension).
# Lab files live in per-lab subdirs in RST; we flatten them under their module.
DOC2MINT = {
    "index": "index",
    "setup/lab-topology": "setup/lab-topology",
    "module1-irules/module1": "module1-irules/index",
    "module1-irules/lab1/lab1-per-ip-rate-limiting": "module1-irules/lab1-per-ip-rate-limiting",
    "module1-irules/lab2/lab2-per-uri-rate-limiting": "module1-irules/lab2-per-uri-rate-limiting",
    "module1-irules/lab3/lab3-concurrent-connections": "module1-irules/lab3-concurrent-connections",
    "module1-irules/lab4/lab4-sliding-window": "module1-irules/lab4-sliding-window",
    "module1-irules/lab5/lab5-custom-signature": "module1-irules/lab5-custom-signature",
    "module2-ltm-policies/module2": "module2-ltm-policies/index",
    "module2-ltm-policies/lab1/lab1-rate-filter": "module2-ltm-policies/lab1-rate-filter",
    "module2-ltm-policies/lab2/lab2-policy-irule": "module2-ltm-policies/lab2-policy-irule",
    "module2-ltm-policies/lab3/lab3-datagroup": "module2-ltm-policies/lab3-datagroup",
    "module2-ltm-policies/lab4/lab4-reject-bad-paths": "module2-ltm-policies/lab4-reject-bad-paths",
    "module3-asm-waf/module3": "module3-asm-waf/index",
    "module3-asm-waf/lab1/lab1-tps-based": "module3-asm-waf/lab1-tps-based",
    "module3-asm-waf/lab2/lab2-stress-based": "module3-asm-waf/lab2-stress-based",
    "module3-asm-waf/lab3/lab3-behavioral-dos": "module3-asm-waf/lab3-behavioral-dos",
    "module3-asm-waf/lab4/lab4-persistent-signatures": "module3-asm-waf/lab4-persistent-signatures",
    "module3-asm-waf/lab5/lab5-bot-defense": "module3-asm-waf/lab5-bot-defense",
    "answer-key": "answer-key",
}

ADMONITION = {
    nodes.note: "Note",
    nodes.important: "Warning",
    nodes.warning: "Warning",
    nodes.tip: "Tip",
    nodes.hint: "Tip",
    nodes.caution: "Warning",
    nodes.attention: "Warning",
    nodes.danger: "Warning",
    nodes.error: "Warning",
}


def mint_link(docname, anchor=""):
    target = DOC2MINT.get(docname)
    if not target:
        return None
    url = "/mint/" + target
    return url + (("#" + anchor) if anchor else "")


def esc_text(s):
    # MDX treats { and < specially in prose. Escape them outside code.
    return s.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}").replace("<", "\\<")


class MDX:
    """Render a resolved doctree node tree to an MDX string."""

    def __init__(self, env, docname):
        self.env = env
        self.docname = docname
        self.title = None

    def _resolve_docname(self, target):
        # :doc:`x` target may be relative to the current doc's directory.
        if target in DOC2MINT:
            return target
        base = os.path.dirname(self.docname)
        joined = os.path.normpath(os.path.join(base, target)) if base else target
        return joined

    # ---- inline rendering (returns a string, no block breaks) ----
    def inline(self, node):
        out = []
        for child in node.children:
            out.append(self.inline_node(child))
        return "".join(out)

    def inline_node(self, node):
        if isinstance(node, nodes.Text):
            return esc_text(node.astext())
        if isinstance(node, nodes.literal):
            return "`" + node.astext() + "`"
        if isinstance(node, (nodes.strong,)):
            return "**" + self.inline(node) + "**"
        if isinstance(node, (nodes.emphasis, nodes.title_reference)):
            return "*" + self.inline(node) + "*"
        if isinstance(node, nodes.reference):
            text = self.inline(node) or node.astext()
            refuri = node.get("refuri", "")
            refid = node.get("refid", "")
            # internal :doc:/:ref: -> mint link when we can map it
            if "refdocname" in node:
                url = mint_link(node["refdocname"], node.get("refid", ""))
                if url:
                    return "[%s](%s)" % (text, url)
            if refuri:
                return "[%s](%s)" % (text, refuri)
            if refid:
                return "[%s](#%s)" % (text, refid)
            return text
        cls = node.__class__.__name__
        if cls == "pending_xref":
            text = self.inline(node) or node.astext()
            reftype = node.get("reftype", "")
            target = node.get("reftarget", "")
            if reftype == "doc":
                dn = self._resolve_docname(target)
                url = mint_link(dn)
                if url:
                    # no explicit caption -> use the destination page title
                    if not text or text == target:
                        tnode = self.env.titles.get(dn)
                        if tnode is not None:
                            text = tnode.astext()
                    return "[%s](%s)" % (text, url)
            return text
        if cls == "literal_strong":
            return "**`" + node.astext() + "`**"
        if cls == "literal_emphasis":
            return "*`" + node.astext() + "`*"
        if cls in ("desc_name", "literal_strong"):
            return "`" + node.astext() + "`"
        if isinstance(node, (nodes.subscript,)):
            return "<sub>" + self.inline(node) + "</sub>"
        if isinstance(node, (nodes.superscript,)):
            return "<sup>" + self.inline(node) + "</sup>"
        if isinstance(node, nodes.footnote_reference):
            return ""
        if isinstance(node, (nodes.problematic, nodes.system_message)):
            return ""
        # fallback: plain text
        return esc_text(node.astext())

    # ---- block rendering (returns a list of MDX lines/blocks) ----
    def blocks(self, node, depth=1):
        out = []
        for child in node.children:
            out.extend(self.block_node(child, depth))
        return out

    def block_node(self, node, depth):
        if isinstance(node, nodes.section):
            res = []
            # section title
            title = next((c for c in node.children if isinstance(c, nodes.title)), None)
            body_children = [c for c in node.children if not isinstance(c, nodes.title)]
            if title is not None:
                if self.title is None and depth == 1:
                    self.title = title.astext()
                else:
                    level = min(depth, 4)
                    res.append("#" * (level + 1) + " " + self.inline(title))
            for c in body_children:
                res.extend(self.block_node(c, depth + 1))
            return res
        if isinstance(node, nodes.paragraph):
            return [self.inline(node)]
        if isinstance(node, nodes.literal_block):
            lang = node.get("language", "") or ""
            if lang in ("default", "none"):
                lang = "text"
            code = node.astext()
            return ["```" + lang + "\n" + code + "\n```"]
        if isinstance(node, nodes.doctest_block):
            return ["```python\n" + node.astext() + "\n```"]
        if isinstance(node, type(node)) and node.__class__ in ADMONITION:
            tag = ADMONITION[node.__class__]
            inner = self.blocks(node, depth)
            body = "\n\n".join(inner)
            body = "\n".join("  " + ln for ln in body.split("\n"))
            return ["<%s>\n%s\n</%s>" % (tag, body, tag)]
        if isinstance(node, nodes.admonition):
            # generic .. admonition:: Title
            title = next((c for c in node.children if isinstance(c, nodes.title)), None)
            inner = self.blocks(node, depth)
            body = "\n\n".join(inner)
            body = "\n".join("  " + ln for ln in body.split("\n"))
            head = (self.inline(title) + "\n\n") if title is not None else ""
            head = "\n".join("  " + ln for ln in head.split("\n")) if head else ""
            return ["<Note>\n%s%s\n</Note>" % (head, body)]
        if isinstance(node, nodes.bullet_list):
            return [self.render_list(node, depth, ordered=False)]
        if isinstance(node, nodes.enumerated_list):
            return [self.render_list(node, depth, ordered=True)]
        if isinstance(node, nodes.table):
            return [self.render_table(node)]
        if isinstance(node, nodes.block_quote):
            inner = self.blocks(node, depth)
            return ["\n".join("> " + ln for blk in inner for ln in blk.split("\n"))]
        if isinstance(node, nodes.transition):
            return ["---"]
        if isinstance(node, (nodes.figure,)):
            return self.render_figure(node)
        if isinstance(node, nodes.image):
            return self.render_image(node)
        if isinstance(node, nodes.definition_list):
            return [self.render_deflist(node, depth)]
        if isinstance(node, nodes.line_block):
            lines = [self.inline(l) for l in node.children if isinstance(l, nodes.line)]
            return ["\n".join(lines)]
        if isinstance(node, (nodes.comment, nodes.system_message, nodes.target,
                             nodes.substitution_definition, nodes.compound)):
            if isinstance(node, nodes.compound):
                return self.blocks(node, depth)
            return []
        if isinstance(node, nodes.topic):
            # e.g. a local contents; skip toctree-ish topics
            return []
        if isinstance(node, nodes.container):
            return self.blocks(node, depth)
        # toctree leaves nothing in the mirror
        if node.__class__.__name__ == "toctree":
            return []
        # fallback: render children as blocks, else inline text
        if node.children:
            return self.blocks(node, depth)
        txt = node.astext().strip()
        return [esc_text(txt)] if txt else []

    def render_list(self, node, depth, ordered):
        lines = []
        i = 1
        for item in node.children:
            if not isinstance(item, nodes.list_item):
                continue
            marker = ("%d." % i) if ordered else "-"
            sub = self.blocks(item, depth)
            # first block on the marker line, rest indented
            text = "\n\n".join(sub).split("\n")
            if not text:
                text = [""]
            lines.append("%s %s" % (marker, text[0]))
            for ln in text[1:]:
                lines.append("   " + ln if ln else "")
            i += 1
        return "\n".join(lines)

    def render_deflist(self, node, depth):
        out = []
        for item in node.children:
            if not isinstance(item, nodes.definition_list_item):
                continue
            term = next((c for c in item.children if isinstance(c, nodes.term)), None)
            definition = next((c for c in item.children if isinstance(c, nodes.definition)), None)
            if term is not None:
                out.append("**" + self.inline(term) + "**")
            if definition is not None:
                out.append("\n\n".join(self.blocks(definition, depth)))
        return "\n\n".join(out)

    def cell_text(self, entry):
        # inline-only rendering of a table cell; join block/newlines to one line
        parts = []
        for child in entry.children:
            if isinstance(child, nodes.paragraph):
                parts.append(self.inline(child))
            elif isinstance(child, nodes.literal_block):
                parts.append("`" + child.astext().replace("\n", " ") + "`")
            elif isinstance(child, nodes.bullet_list):
                parts.append(" ".join("• " + self.inline(li) for li in child.children))
            else:
                parts.append(esc_text(child.astext()))
        txt = " ".join(p for p in parts if p)
        txt = re.sub(r"\s*\n\s*", " ", txt).strip()
        return txt.replace("|", "\\|")

    def render_table(self, node):
        tgroup = next((c for c in node.children if isinstance(c, nodes.tgroup)), None)
        if tgroup is None:
            return ""
        ncols = sum(1 for c in tgroup.children if isinstance(c, nodes.colspec))
        head = next((c for c in tgroup.children if isinstance(c, nodes.thead)), None)
        body = next((c for c in tgroup.children if isinstance(c, nodes.tbody)), None)

        def row_cells(row):
            return [self.cell_text(e) for e in row.children if isinstance(e, nodes.entry)]

        lines = []
        if head is not None:
            hrows = [r for r in head.children if isinstance(r, nodes.row)]
            header = row_cells(hrows[0]) if hrows else [""] * ncols
        else:
            header = [""] * ncols
        header = (header + [""] * ncols)[:ncols]
        lines.append("| " + " | ".join(header) + " |")
        lines.append("| " + " | ".join(["---"] * ncols) + " |")
        if body is not None:
            for r in body.children:
                if not isinstance(r, nodes.row):
                    continue
                cells = (row_cells(r) + [""] * ncols)[:ncols]
                lines.append("| " + " | ".join(cells) + " |")
        return "\n".join(lines)

    def render_figure(self, node):
        img = next((c for c in node.children if isinstance(c, nodes.image)), None)
        caption = next((c for c in node.children if isinstance(c, nodes.caption)), None)
        out = self.render_image(img) if img is not None else []
        if caption is not None:
            out.append("*" + self.inline(caption) + "*")
        return out

    def render_image(self, node):
        uri = (node.get("uri") or "").lstrip("/")
        alt = node.get("alt", "")
        # Images live under docs/_static; they are not part of the Mintlify
        # mirror unless copied. Emit an Info placeholder so the page still
        # renders and the missing asset is obvious.
        if uri.startswith("_static") or not uri:
            label = alt or os.path.basename(uri) or "screenshot"
            return ["<Info>Screenshot: **%s** (see the PDF/HTML guide).</Info>" % label]
        return ["![%s](%s)" % (alt, uri)]


def convert(app, docname):
    env = app.env
    doctree = env.get_doctree(docname)
    r = MDX(env, docname)
    body_blocks = r.blocks(doctree, depth=1)
    title = r.title or docname.split("/")[-1]
    body = "\n\n".join(b for b in body_blocks if b.strip())
    # collapse 3+ blank lines
    body = re.sub(r"\n{3,}", "\n\n", body)
    fm = "---\ntitle: %s\n---\n\n" % _yaml(title)
    mintpath = DOC2MINT[docname]
    dest = os.path.join(OUTDIR, mintpath + ".mdx")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w") as f:
        f.write(fm + body + "\n")
    return dest


def _yaml(s):
    s = s.strip()
    if re.search(r"[:#\"']", s):
        return '"' + s.replace('"', '\\"') + '"'
    return s


def main():
    import tempfile
    doctreedir = tempfile.mkdtemp(prefix="rst2mdx-doctrees-")
    outbuild = tempfile.mkdtemp(prefix="rst2mdx-out-")
    app = Sphinx(SRCDIR, SRCDIR, outbuild, doctreedir, "dummy",
                 freshenv=True, warningiserror=False)
    app.build()
    made = []
    for docname in DOC2MINT:
        try:
            made.append(convert(app, docname))
        except Exception as e:  # noqa
            print("FAIL %s: %s" % (docname, e), file=sys.stderr)
            raise
    for m in made:
        print("wrote", os.path.relpath(m, REPO))
    print("TOTAL", len(made), "pages")


if __name__ == "__main__":
    main()
