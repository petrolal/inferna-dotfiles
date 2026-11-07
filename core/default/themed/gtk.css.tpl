/* Named colors GTK3/4's stock Adwaita theme reads for its accent chrome
   (selection highlight, checkboxes, the active row in Thunar's sidebar and
   file list). Without these every Inferna theme looks identical in GTK apps
   -- Adwaita's own default blue -- regardless of the theme's own accent. */
@define-color accent_color {{ accent }};
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color {{ bright_foreground }};
@define-color theme_selected_bg_color {{ accent }};
@define-color theme_selected_fg_color {{ bright_foreground }};
@define-color selected_bg_color {{ accent }};
@define-color selected_fg_color {{ bright_foreground }};
