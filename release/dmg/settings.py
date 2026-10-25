"""Finder layout, written directly without scripting Finder or System Events."""
from pathlib import Path

app = Path(defines['app']).resolve()
format = 'UDZO'
filesystem = 'HFS+'
files = [(str(app), 'Duo Receiver.app')]
symlinks = {'Applications': '/Applications'}
background = str(Path(defines['background']).resolve())
icon = str(app / 'Contents/Resources/AppIcon.icns')
window_rect = ((160, 160), (720, 460))
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
include_icon_view_settings = True
include_list_view_settings = False
icon_size = 104
text_size = 13
label_pos = 'bottom'
icon_locations = {'Duo Receiver.app': (190, 249), 'Applications': (530, 249)}
# Do not set FinderInfo on the signed app: it invalidates codesign --strict.
