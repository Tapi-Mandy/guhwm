/* ================== APPEARANCE ================== */
static const unsigned int borderpx  = 2;        /* border pixel of windows */
static const unsigned int snap      = 32;       /* snap pixel */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 0 means bottom bar */

/* Fonts */
static const char *fonts[]          = { "monospace:size=13" };
static const char dmenufont[]       = "monospace:size=13";


/* ================== THEME SELECTOR ==================
Uncomment ONE theme */

#define THEME_MIDNIGHT_ROSE /* DEFAULT */
// #define THEME_MONOCHROME
// #define THEME_NORD
// #define THEME_DRACULA
// #define THEME_SOLARIZED
// #define THEME_ONEDARK

/* ------------------     THEMES    ------------------ */

/* ================== MIDNIGHT ROSE ==================
   Dark, moody background with a warm rose accent.
   Great if you like a balance between gruvbox-dark and rose highlights. */

#if defined(THEME_MIDNIGHT_ROSE)
static const char col_bg[]     = "#282828";  /* background (very dark gray) */
static const char col_fg[]     = "#d4be98";  /* normal foreground (beige/soft white text) */
static const char col_border[] = "#444444";  /* window border (medium gray) */
static const char col_accent[] = "#d3869b";  /* accent (rose pink/purple for highlights) */
static const char col_fgsel[]  = "#eeeeee";  /* foreground (text on selected window/bar) */

/* ================== MONOCHROME ==================
   Soft grayscale palette.
   Minimal, neutral, and easy on the eyes. */

#elif defined(THEME_MONOCHROME)
static const char col_bg[]     = "#1e1e1e";  /* dark gray background */
static const char col_fg[]     = "#dcdcdc";  /* light gray foreground */
static const char col_border[] = "#3c3c3c";  /* medium-dark gray for borders */
static const char col_accent[] = "#aaaaaa";  /* mid-gray accent */
static const char col_fgsel[]  = "#ffffff";  /* bright white for selected fg */

/* ================== NORD ==================
   Cold, calm theme inspired by Arctic tones.
   Lots of blue and gray, easy on the eyes. */

#elif defined(THEME_NORD)
static const char col_bg[]     = "#2e3440";  /* background (dark blue-gray) */
static const char col_fg[]     = "#d8dee9";  /* normal foreground (light icy gray text) */
static const char col_border[] = "#3b4252";  /* window border (slate gray) */
static const char col_accent[] = "#88c0d0";  /* accent (icy cyan) */
static const char col_fgsel[]  = "#eceff4";  /* foreground (brighter white for selected win) */

/* ================== DRACULA ==================
   Popular dark theme with neon accents.
   Purple is the main highlight color. */

#elif defined(THEME_DRACULA)
static const char col_bg[]     = "#282a36";  /* background (almost black with a hint of blue) */
static const char col_fg[]     = "#f8f8f2";  /* normal foreground (off-white text) */
static const char col_border[] = "#44475a";  /* window border (muted grayish blue) */
static const char col_accent[] = "#bd93f9";  /* accent (neon purple) */
static const char col_fgsel[]  = "#ffffff";  /* foreground (pure white for selected win) */

/* ================== SOLARIZED DARK ==================
   Classic theme, softer contrast.
   Uses a teal-blue accent with earthy backgrounds. */

#elif defined(THEME_SOLARIZED)
static const char col_bg[]     = "#002b36";  /* background (deep cyan/blue) */
static const char col_fg[]     = "#839496";  /* normal foreground (muted gray-cyan text) */
static const char col_border[] = "#073642";  /* window border (dark teal) */
static const char col_accent[] = "#268bd2";  /* accent (sky blue) */
static const char col_fgsel[]  = "#fdf6e3";  /* foreground (cream white for selected win) */

/* ================== ONE DARK ==================
   From Atom/VSCode.
   Neutral dark background with colorful accents. */

#elif defined(THEME_ONEDARK)
static const char col_bg[]     = "#282c34";  /* background (dark neutral gray) */
static const char col_fg[]     = "#abb2bf";  /* normal foreground (grayish white text) */
static const char col_border[] = "#3e4451";  /* window border (steel gray) */
static const char col_accent[] = "#61afef";  /* accent (bright sky blue) */
static const char col_fgsel[]  = "#ffffff";  /* foreground (white for selected win) */

/* ---- Fallback (MIDNIGHT ROSE) ---- */
#else
static const char col_bg[]     = "#282828";
static const char col_fg[]     = "#d4be98";
static const char col_border[] = "#444444";
static const char col_accent[] = "#d3869b";
static const char col_fgsel[]  = "#eeeeee";
#endif

/* ================== NOTES ==================
- To change theme, just swap which #define THEME_* is uncommented above.
- Recompile guhwm after switching.

- If you want to experiment with other accent colors:

 // "#dc143c";  /* crimson red */
 // "#8ec07c";  /* mint green */
 // "#fe8019";  /* bright orange */
 // "#689d6a";  /* dark green */
 // "#d65d0e";  /* deep orange */
 // "#b8a1e3";  /* lavender/purple */
 // "#8be9fd";  /* cyan/light blue */
 // "#ff79c6";  /* neon pink */
 // "#50fa7b";  /* bright green */
 // "#f1fa8c";  /* pastel yellow */

/* ---- Example usage ----
static const char col_accent[] = "#dc143c"; (Crimson Red)
*/

/* fg = text color, bg = bar/window background, border = window border */
static const char *colors[][3] = {
	/*               fg        bg        border   */
	[SchemeNorm] = { col_fg,   col_bg,   col_border },
	[SchemeSel]  = { col_fgsel,col_accent,col_accent },
};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* xprop(1):
	 *	WM_CLASS(STRING) = instance, class
	 *	WM_NAME(STRING) = title
	 */
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "Gimp",     NULL,       NULL,       0,            1,           -1 },
	{ "Firefox",  NULL,       NULL,       1 << 8,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */
static const int refreshrate = 120;  /* refresh rate (per second) for client move/resize */

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },    /* first entry is default */
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* key definitions */
#define MODKEY Mod1Mask
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { 
    "dmenu_run", 
    "-m", dmenumon, 
    "-fn", dmenufont, 
    "-nb", col_bg,      /* background */
    "-nf", col_fg,      /* normal text */
    "-sb", col_accent,  /* selected background (accent) */
    "-sf", col_fgsel,   /* selected text */
    NULL 
};
static const char *roficmd[] = { 
    "rofi", 
    "-show", "drun",
    "-theme-str", "* { background: " col_bg "; }",
    "-theme-str", "* { foreground: " col_fg "; }",
    "-theme-str", "window { background-color: " col_bg "; }",
    "-theme-str", "mainbox { background-color: " col_bg "; }",
    "-theme-str", "listview { background-color: " col_bg "; }",
    "-theme-str", "element { background-color: " col_bg "; foreground: " col_fg "; }",
    "-theme-str", "element selected { background-color: " col_accent "; foreground: " col_fgsel "; }",
    NULL 
};
static const char *termcmd[]  = { "kitty", NULL };
static const char *clipmenucmd[] = { "clipmenu", NULL };

static const Key keys[] = {
    /* modifier                     key        function        argument */
    /* Keybinding for dmenu */
    { MODKEY,                       XK_p,      spawn,          {.v = dmenucmd } },
    /* Keybinding for rofi (if installed) */
    { MODKEY|ShiftMask,             XK_d,      spawn,          {.v = roficmd } },
    /* Keybinding for Kitty */
    { MODKEY|ShiftMask,             XK_Return, spawn,          {.v = termcmd } },
    /* Keybinding for clipmenu */
    { MODKEY|ShiftMask,             XK_x,      spawn,          {.v = clipmenucmd } },
    /* Keybindings for scrot */
    { 0,                            XK_Print,  spawn,          SHCMD("scrot -s") }, /* Screenshots selected area */
    { ShiftMask,                    XK_Print,  spawn,          SHCMD("scrot") }, /* Screenshots fullscreen */
    /* ---------------------------------------------------------- */
    { MODKEY,                       XK_b,      togglebar,      {0} },
    { MODKEY,                       XK_j,      focusstack,     {.i = +1 } },
    { MODKEY,                       XK_k,      focusstack,     {.i = -1 } },
    { MODKEY,                       XK_i,      incnmaster,     {.i = +1 } },
    { MODKEY,                       XK_d,      incnmaster,     {.i = -1 } },
    { MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
    { MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },
    { MODKEY,                       XK_Return, zoom,           {0} },
    { MODKEY,                       XK_Tab,    view,           {0} },
    { MODKEY,                       XK_q,      killclient,     {0} },
    { MODKEY,                       XK_t,      setlayout,      {.v = &layouts[0]} },
    { MODKEY,                       XK_f,      setlayout,      {.v = &layouts[1]} },
    { MODKEY,                       XK_m,      setlayout,      {.v = &layouts[2]} },
    { MODKEY,                       XK_space,  setlayout,      {0} },
    { MODKEY|ShiftMask,             XK_space,  togglefloating, {0} },
    { MODKEY,                       XK_0,      view,           {.ui = ~0 } },
    { MODKEY|ShiftMask,             XK_0,      tag,            {.ui = ~0 } },
    { MODKEY,                       XK_comma,  focusmon,       {.i = -1 } },
    { MODKEY,                       XK_period, focusmon,       {.i = +1 } },
    { MODKEY|ShiftMask,             XK_comma,  tagmon,         {.i = -1 } },
    { MODKEY|ShiftMask,             XK_period, tagmon,         {.i = +1 } },
    TAGKEYS(                        XK_1,                      0)
    TAGKEYS(                        XK_2,                      1)
    TAGKEYS(                        XK_3,                      2)
    TAGKEYS(                        XK_4,                      3)
    TAGKEYS(                        XK_5,                      4)
    TAGKEYS(                        XK_6,                      5)
    TAGKEYS(                        XK_7,                      6)
    TAGKEYS(                        XK_8,                      7)
    TAGKEYS(                        XK_9,                      8)
    { MODKEY|ShiftMask,             XK_q,      quit,           {0} },
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
