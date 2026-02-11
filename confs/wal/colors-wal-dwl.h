/* Taken from https://github.com/djpohly/dwl/issues/466 */
#define COLOR(hex)    { ((hex >> 24) & 0xFF) / 255.0f, \
                        ((hex >> 16) & 0xFF) / 255.0f, \
                        ((hex >> 8) & 0xFF) / 255.0f, \
                        (hex & 0xFF) / 255.0f }

static const float rootcolor[]             = COLOR(0x0f0a17ff);
static uint32_t colors[][3]                = {
	/*               fg          bg          border    */
	[SchemeNorm] = { 0xc3c1c5ff, 0x0f0a17ff, 0x62596dff },
	[SchemeSel]  = { 0xc3c1c5ff, 0xE2A055ff, 0xBB554Bff },
	[SchemeUrg]  = { 0xc3c1c5ff, 0xBB554Bff, 0xE2A055ff },
};
