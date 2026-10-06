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
        return StaticGroupedFlowables([_orig_litblock_build(self)],
                                      style=_keep_together_style)
    _rinoh_rst_nodes.Literal_Block.build_flowable = _litblock_keep_together
except Exception:
    pass
