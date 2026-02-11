static const char norm_fg[] = "#c3c1c5";
static const char norm_bg[] = "#0f0a17";
static const char norm_border[] = "#62596d";

static const char sel_fg[] = "#c3c1c5";
static const char sel_bg[] = "#E2A055";
static const char sel_border[] = "#c3c1c5";

static const char urg_fg[] = "#c3c1c5";
static const char urg_bg[] = "#BB554B";
static const char urg_border[] = "#BB554B";

static const char *colors[][3]      = {
    /*               fg           bg         border                         */
    [SchemeNorm] = { norm_fg,     norm_bg,   norm_border }, // unfocused wins
    [SchemeSel]  = { sel_fg,      sel_bg,    sel_border },  // the focused win
    [SchemeUrg] =  { urg_fg,      urg_bg,    urg_border },
};
