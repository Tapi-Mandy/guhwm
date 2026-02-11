static const char norm_fg[] = "#e5deda";
static const char norm_bg[] = "#4a3c33";
static const char norm_border[] = "#a09b98";

static const char sel_fg[] = "#e5deda";
static const char sel_bg[] = "#BBA597";
static const char sel_border[] = "#e5deda";

static const char urg_fg[] = "#e5deda";
static const char urg_bg[] = "#B19B8D";
static const char urg_border[] = "#B19B8D";

static const char *colors[][3]      = {
    /*               fg           bg         border                         */
    [SchemeNorm] = { norm_fg,     norm_bg,   norm_border }, // unfocused wins
    [SchemeSel]  = { sel_fg,      sel_bg,    sel_border },  // the focused win
    [SchemeUrg] =  { urg_fg,      urg_bg,    urg_border },
};
