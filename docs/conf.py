import os
import sys

project = 'BIG-IP L7DoS Lab'
copyright = '2026, F5 Lab'
author = 'F5 Lab'
release = '1.0'

extensions = [
    'sphinx.ext.autosectionlabel',
]

templates_path = ['_templates']
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']
html_theme_options = {
    'navigation_depth': 4,
    'collapse_navigation': False,
    'sticky_navigation': True,
    'includehidden': True,
    'titles_only': False,
}
html_show_sourcelink = False

# --- PDF (rinohtype) build: single combined lab guide ---
try:
    import rinoh.frontend.sphinx  # noqa: F401
    extensions.append('rinoh.frontend.sphinx')
except ImportError:
    pass
rinoh_documents = [{
    'doc': 'index',
    'target': 'BIG-IP-L7DoS-Lab-Guide',
    'title': 'BIG-IP Layer 7 DoS Lab Guide',
    'subtitle': 'Modules 1-3 - iRules, LTM Policies, ASM/Advanced WAF',
}]

# Keep code/literal blocks together on one page so no iRule or config snippet
# spans a page break. rinohtype has no per-paragraph "keep together", but
# GroupedFlowables supports same_page; wrap each literal block in a same_page
# group. The code-block style matches by type (+CodeBlock), so nesting it does
# not change its appearance.
try:
    from rinoh.frontend.rst import nodes as _rinoh_rst_nodes
    from rinoh.flowable import StaticGroupedFlowables, GroupedFlowablesStyle
    _keep_together_style = GroupedFlowablesStyle(same_page=True)
    _orig_litblock_build = _rinoh_rst_nodes.Literal_Block.build_flowable
    def _litblock_keep_together(self):
        inner = _orig_litblock_build(self)
        text = getattr(self, 'text', '') or ''
        if text.count('\n') <= 45:
            return StaticGroupedFlowables([inner], style=_keep_together_style)
        return inner
    _rinoh_rst_nodes.Literal_Block.build_flowable = _litblock_keep_together
except Exception:
    pass

# Inline literals (``code`` spans) are monospace tokens that rinohtype will only
# break at whitespace or "/". A long literal with none of those (e.g.
# ``browser-verify-after-access-detection`` or ``10.1.10.55:80``) cannot wrap,
# so inside a narrow table cell it overflows the column border and runs into the
# neighbouring cell. Insert zero-width-space (U+200B) break opportunities after
# natural boundary characters so such literals wrap INSIDE their own cell.
# U+200B is a break opportunity only: it emits no glyph and is not added to the
# PDF text layer, so selecting/copying the literal yields the original text with
# no stray character (verified with pdftotext). It only triggers a break when a
# line would otherwise overflow, so short tokens (IPs that fit) are untouched.
try:
    import re as _rinoh_re
    import rinoh as _rinoh_rt
    from rinoh.frontend.rst import nodes as _rinoh_inline_nodes
    _ZWSP = '​'
    _ZWSP_BOUNDARY = _rinoh_re.compile(r'([-_./:,])')
    _ZWSP_LONGRUN = _rinoh_re.compile(r'[^\s' + _ZWSP + r']{20,}')

    def _insert_break_opportunities(text):
        if not text or len(text) < 12:
            return text
        out = _ZWSP_BOUNDARY.sub(r'\1' + _ZWSP, text)

        def _chunk(match):
            run = match.group(0)
            return _ZWSP.join(run[i:i + 14] for i in range(0, len(run), 14))

        return _ZWSP_LONGRUN.sub(_chunk, out)

    def _literal_build_styled_text(self, strip_leading_whitespace=False):
        txt = getattr(self, 'text', '') or ''
        return _rinoh_rt.SingleStyledText(_insert_break_opportunities(txt),
                                          style=self.style_from_class)

    _rinoh_inline_nodes.Literal.build_styled_text = _literal_build_styled_text
except Exception:
    pass
