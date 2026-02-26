/**
 * @file font_test.c
 * @brief Font debug visualization screen — multi-page with D-pad navigation.
 *
 * Activated via --font-test CLI flag. Replaces the normal game boot
 * with rotating screens showcasing every font type and UI element in the
 * CPS3 screen-font engine.
 *
 * Controls:
 *   LEFT/RIGHT  — Manual page navigation
 *   Auto-cycles every ~10 seconds if no input
 *
 * Pages:
 *   0:  Fixed-Width — Full Charset & Palettes
 *   1:  Fixed-Width — Style Variations & Comparisons
 *   2:  Proportional — Charset, Centering, Width Comparison
 *   3:  Proportional — Vertex Colors & In-Game Messages
 *   4:  Proportional Scaled (SSPutStrPro_Scale)
 *   5:  Bigger/Scaled Fonts — Sizes & Gradients
 *   6:  Score Digits & Decimal Numbers
 *   7:  Tile Blocks & ATR Flips
 *   8:  Health, Stun, & HUD Bars
 *   9:  Screen Transitions (Animated)
 *  10:  In-Game HUD Recreation
 */

#include "sf33rd/Source/Game/debug/font_test.h"
#include "common.h"
#include "main.h"
#include "port/renderer.h"
#include "sf33rd/Source/Common/PPGFile.h"
#include "sf33rd/Source/Common/PPGWork.h"
#include "sf33rd/Source/Game/engine/workuser.h"
#include "sf33rd/Source/Game/system/sysdir.h"
#include "sf33rd/Source/Game/system/work_sys.h"
#include "sf33rd/Source/Game/ui/sc_sub.h"
#include "sf33rd/AcrSDK/common/pad.h"

#define PAGE_COUNT      11
#define FRAMES_PER_PAGE 596  /* ~10 seconds at 59.6 FPS */

/* ════════════════════════════════════════════════════════════════
 *  Page 0: Fixed-Width — Full Charset & Palettes
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page0(void) {
    u8 p;

    SSPutStr(1, 0, 4, "PAGE 1: FIXED 8x8 CHARSET");

    SSPutStr(0, 2, 1, "UPPERCASE:");
    SSPutStr(1, 3, 4, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");

    SSPutStr(0, 4, 1, "LOWERCASE:");
    SSPutStr(1, 5, 4, "abcdefghijklmnopqrstuvwxyz");

    SSPutStr(0, 6, 1, "DIGITS + SYMBOLS:");
    SSPutStr(1, 7, 4, "0123456789 .:;!?+-=()[]<>");

    SSPutStr(0, 9, 1, "COMMA TRICK (2PX DROP):");
    SSPutStr(1, 10, 4, "NO COMMA: ABCDEFG");
    SSPutStr(1, 11, 4, "W, COMMA: A,B,C,D,E,F,G");

    SSPutStr(0, 13, 1, "ALL 16 PALETTES:");
    for (p = 0; p < 16; p++) {
        SSPutDec(0, 14 + p, 1, p, 2);
        SSPutStr(3, 14 + p, p, "ABCDEF 012345 abcdef");
    }
}

/* ════════════════════════════════════════════════════════════════
 *  Page 1: Fixed-Width — Style Variations
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page1(void) {
    SSPutStr(1, 0, 4, "PAGE 2: FIXED 8x8 VARIATIONS");

    SSPutStr(0, 2, 1, "SSPUTSTR (TEXTURE PAGE 1):");
    SSPutStr(1, 3, 4, "STANDARD FIXED-WIDTH TEXT");
    SSPutStr(1, 4, 1, "PALETTE 1 CYAN TEXT SAMPLE");
    SSPutStr(1, 5, 8, "PALETTE 8 TEAL TEXT SAMPLE");
    SSPutStr(1, 6, 9, "PALETTE 9 DARK RED SAMPLE");

    SSPutStr(0, 8, 1, "SSPUTSTR2 (TEXTURE PAGE 3):");
    SSPutStr2(1, 9, 4, "SSPUTSTR2 YELLOW PALETTE 4");
    SSPutStr2(1, 10, 1, "SSPUTSTR2 CYAN   PALETTE 1");
    SSPutStr2(1, 11, 8, "SSPUTSTR2 TEAL   PALETTE 8");

    SSPutStr(0, 13, 1, "SIDE BY SIDE PAGE 1 VS 3:");
    SSPutStr(1, 14, 4, "PAGE1: ABCDEF 012345");
    SSPutStr2(1, 15, 4, "PAGE3: ABCDEF 012345");

    SSPutStr(0, 17, 1, "SSPUTDEC (DECIMAL RENDER):");
    SSPutStr(1, 18, 1, "SIZE=1:");
    SSPutDec(9, 18, 4, 0, 1);
    SSPutDec(11, 18, 4, 5, 1);
    SSPutDec(13, 18, 4, 9, 1);
    SSPutStr(1, 19, 1, "SIZE=2:");
    SSPutDec(9, 19, 4, 0, 2);
    SSPutDec(13, 19, 4, 42, 2);
    SSPutDec(17, 19, 4, 99, 2);
    SSPutStr(1, 20, 1, "SIZE=3:");
    SSPutDec(9, 20, 4, 0, 3);
    SSPutDec(14, 20, 4, 100, 3);
    SSPutDec(19, 20, 4, 255, 3);

    SSPutStr(0, 22, 1, "PALETTE + ALIGNMENT:");
    SSPutStr(0, 23, 4, "LEFT ALIGN  X=0");
    SSPutStr(16, 24, 4, "CENTER AREA X=16");
    SSPutStr(24, 25, 4, "RIGHT AREA X=24");
}

/* ════════════════════════════════════════════════════════════════
 *  Page 2: Proportional — Charset & Centering
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page2(void) {
    s8 upper[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    s8 lower[] = "abcdefghijklmnopqrstuvwxyz";
    s8 digits[] = "0123456789";
    s8 narrow[] = "iIl1!.:;|";
    s8 wide[] = "MWmwQOGD@";
    s8 ctr[] = "CENTERED (FLAG=1)";
    s8 left[] = "LEFT ALIGNED (FLAG=0)";
    s8 fw_comp[] = "FIXED WIDTH";
    s8 pr_comp[] = "FIXED WIDTH";

    SSPutStr(1, 0, 4, "PAGE 3: PROPORTIONAL CHARSET");

    SSPutStr(0, 2, 1, "UPPERCASE:");
    SSPutStrPro(0, 1 * 8, 3 * 8, 4, 0xFFFFFFFF, upper);

    SSPutStr(0, 4, 1, "LOWERCASE:");
    SSPutStrPro(0, 1 * 8, 5 * 8, 4, 0xFFFFFFFF, lower);

    SSPutStr(0, 6, 1, "DIGITS:");
    SSPutStrPro(0, 1 * 8, 7 * 8, 4, 0xFFFFFFFF, digits);

    SSPutStr(0, 9, 1, "NARROW GLYPHS (TRIMMED SIDES):");
    SSPutStrPro(0, 1 * 8, 10 * 8, 4, 0xFFFFFF00, narrow);

    SSPutStr(0, 11, 1, "WIDE GLYPHS (FULL WIDTH):");
    SSPutStrPro(0, 1 * 8, 12 * 8, 4, 0xFFFF8800, wide);

    SSPutStr(0, 14, 1, "CENTERING FLAG:");
    SSPutStrPro(1, 192, 15 * 8, 4, 0xFFFFFFFF, ctr);
    SSPutStr(16, 15, 1, "|");
    SSPutStrPro(0, 1 * 8, 16 * 8, 8, 0xFFFFFFFF, left);

    SSPutStr(0, 18, 1, "FIXED (8PX) VS PROPORTIONAL:");
    SSPutStr(1, 19, 4, "FIXED: iIl1MWQO");
    SSPutStrPro(0, 1 * 8, 20 * 8, 8, 0xFFFFFFFF, narrow);
    SSPutStrPro(0, 10 * 8, 20 * 8, 8, 0xFFFFFFFF, wide);

    SSPutStr(0, 22, 1, "SAME TEXT BOTH FONTS:");
    SSPutStr(1, 23, 4, "FIXED WIDTH");
    SSPutStrPro(0, 1 * 8, 24 * 8, 8, 0xFFFFFFFF, pr_comp);

    SSPutStr(0, 26, 1, "PROPORTIONAL PALETTES:");
    SSPutStrPro(0, 1 * 8, 27 * 8, 1, 0xFFFFFFFF, fw_comp);
    SSPutStrPro(0, 16 * 8, 27 * 8, 4, 0xFFFFFFFF, fw_comp);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 3: Proportional — Vertex Colors & Messages
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page3(void) {
    s8 red[] = "RED FF0000";
    s8 grn[] = "GREEN 00FF00";
    s8 blu[] = "BLUE 0000FF";
    s8 ylw[] = "YELLOW FFFF00";
    s8 cyn[] = "CYAN 00FFFF";
    s8 mag[] = "MAGENTA FF00FF";
    s8 org[] = "ORANGE FF8800";
    s8 wht[] = "WHITE FFFFFF";
    s8 a80[] = "ALPHA 80 (SEMI-TRANSPARENT)";
    s8 a40[] = "ALPHA 40 (VERY TRANSPARENT)";
    s8 r1[] = "ROUND 1";
    s8 fgt[] = "FIGHT!";
    s8 ko[] = "K.O.";
    s8 win[] = "YOU WIN";
    s8 perf[] = "PERFECT";
    s8 dko[] = "DOUBLE K.O.";
    s8 tov[] = "TIME OVER";

    SSPutStr(1, 0, 4, "PAGE 4: PROPORTIONAL COLORS");

    SSPutStr(0, 2, 1, "VERTEX COLORS (0xAARRGGBB):");
    SSPutStrPro(0, 1 * 8, 3 * 8, 4, 0xFFFF0000, red);
    SSPutStrPro(0, 1 * 8, 4 * 8, 4, 0xFF00FF00, grn);
    SSPutStrPro(0, 1 * 8, 5 * 8, 4, 0xFF0000FF, blu);
    SSPutStrPro(0, 1 * 8, 6 * 8, 4, 0xFFFFFF00, ylw);
    SSPutStrPro(0, 1 * 8, 7 * 8, 4, 0xFF00FFFF, cyn);
    SSPutStrPro(0, 1 * 8, 8 * 8, 4, 0xFFFF00FF, mag);
    SSPutStrPro(0, 1 * 8, 9 * 8, 4, 0xFFFF8800, org);
    SSPutStrPro(0, 1 * 8, 10 * 8, 4, 0xFFFFFFFF, wht);

    SSPutStr(0, 12, 1, "ALPHA BLENDING:");
    SSPutStrPro(0, 1 * 8, 13 * 8, 4, 0x80FFFFFF, a80);
    SSPutStrPro(0, 1 * 8, 14 * 8, 4, 0x40FFFFFF, a40);

    SSPutStr(0, 16, 1, "IN-GAME MESSAGE STYLE:");
    SSPutStrPro(1, 192, 17 * 8, 4, 0xFFFFFFFF, r1);
    SSPutStrPro(1, 192, 18 * 8, 4, 0xFFFF0000, fgt);
    SSPutStrPro(1, 192, 20 * 8, 4, 0xFFFFFF00, ko);
    SSPutStrPro(1, 192, 22 * 8, 4, 0xFF00FF00, win);
    SSPutStrPro(0, 20 * 8, 22 * 8, 4, 0xFFFF00FF, perf);
    SSPutStrPro(1, 192, 24 * 8, 4, 0xFFFF0000, dko);
    SSPutStrPro(1, 192, 26 * 8, 4, 0xFFFFFF00, tov);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 4: Proportional Scaled (SSPutStrPro_Scale)
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page4(void) {
    s8 s10[] = "Scale 1.0x";
    s8 s12[] = "Scale 1.2x";
    s8 s15[] = "Scale 1.5x";
    s8 s20[] = "Scale 2.0x";
    s8 s25[] = "Scale 2.5x";
    s8 s30[] = "Scale 3.0x";
    s8 abc[] = "ABCDEFGHIJKL";
    s8 mix[] = "Scaled Proportional";

    SSPutStr(1, 0, 4, "PAGE 5: PRO_SCALE (SCALED PROP)");

    SSPutStr(0, 2, 1, "SCALE COMPARISON:");
    SSPutStrPro_Scale(0, 1 * 8, 3 * 8, 4, 0xFFFFFFFF, s10, 1.0f);
    SSPutStrPro_Scale(0, 1 * 8, 4.5f * 8, 4, 0xFFFFFFFF, s12, 1.2f);
    SSPutStrPro_Scale(0, 1 * 8, 6.0f * 8, 4, 0xFFFFFFFF, s15, 1.5f);
    SSPutStrPro_Scale(0, 1 * 8, 8.0f * 8, 4, 0xFFFFFFFF, s20, 2.0f);
    SSPutStrPro_Scale(0, 1 * 8, 10.5f * 8, 4, 0xFFFFFFFF, s25, 2.5f);
    SSPutStrPro_Scale(0, 1 * 8, 13.5f * 8, 4, 0xFFFFFFFF, s30, 3.0f);

    SSPutStr(0, 17, 1, "SCALED + VERTEX COLOR:");
    SSPutStrPro_Scale(0, 1 * 8, 18 * 8, 4, 0xFFFF0000, abc, 1.5f);
    SSPutStrPro_Scale(0, 1 * 8, 20 * 8, 4, 0xFF00FF00, abc, 1.5f);
    SSPutStrPro_Scale(0, 1 * 8, 22 * 8, 4, 0xFFFFFF00, abc, 1.5f);

    SSPutStr(0, 24, 1, "SCALED + CENTERED (FLAG=1):");
    SSPutStrPro_Scale(1, 192, 25 * 8, 4, 0xFFFFFFFF, mix, 1.5f);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 5: Bigger/Scaled Fonts — Sizes & Gradients
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page5(void) {
    s8 s10[] = "SCALE 1X";
    s8 s15[] = "SCALE 1.5";
    s8 s20[] = "SCALE 2X";
    s8 g0[] = "GRADIENT 0";
    s8 g1[] = "GRADIENT 1";
    s8 g2[] = "GRADIENT 2";
    s8 half[] = "A$B$C$D";

    SSPutStr(1, 0, 4, "PAGE 6: BIGGER FONT + GRADIENTS");

    SSPutStr(0, 2, 1, "1.0X SCALE:");
    SSPutStr_Bigger(1 * 8, 3 * 8, 4, s10, 1.0f, 0, 2);

    SSPutStr(0, 5, 1, "1.5X SCALE:");
    SSPutStr_Bigger(1 * 8, 6 * 8, 4, s15, 1.5f, 0, 2);

    SSPutStr(0, 8, 1, "2.0X SCALE:");
    SSPutStr_Bigger(1 * 8, 9 * 8, 4, s20, 2.0f, 0, 2);

    SSPutStr(0, 12, 1, "GRADIENT 0 (GOLD):");
    SSPutStr_Bigger(1 * 8, 13 * 8, 4, g0, 1.5f, 0, 2);

    SSPutStr(0, 15, 1, "GRADIENT 1 (MULTI):");
    SSPutStr_Bigger(1 * 8, 16 * 8, 4, g1, 1.5f, 1, 2);

    SSPutStr(0, 18, 1, "GRADIENT 2 (WARM):");
    SSPutStr_Bigger(1 * 8, 19 * 8, 4, g2, 1.5f, 2, 2);

    SSPutStr(0, 22, 1, "HALF-SPACE ($) TOKEN:");
    SSPutStr_Bigger(1 * 8, 23 * 8, 4, half, 2.0f, 0, 2);
    SSPutStr(1, 25, 1, "$ = INLINE HALF-WIDTH SPACE");
}

/* ════════════════════════════════════════════════════════════════
 *  Page 6: Score Digits
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page6(void) {
    u8 d;

    SSPutStr(1, 0, 4, "PAGE 7: SCORE DIGIT FONTS");

    SSPutStr(0, 2, 1, "SCORE 8x16 (SCORE8X16_PUT):");
    for (d = 0; d < 10; d++) {
        score8x16_put(1 + d, 3, 8, d);
    }
    SSPutStr(0, 5, 1, "SCORE 8x16 PAL 4:");
    for (d = 0; d < 10; d++) {
        score8x16_put(1 + d, 6, 4, d);
    }

    SSPutStr(0, 9, 1, "SCORE 16x24 (SCORE16X24_PUT):");
    for (d = 0; d < 10; d++) {
        score16x24_put(1 + (d * 2), 10, 8, d);
    }

    SSPutStr(0, 14, 1, "SCORE 16x24 PAL 4:");
    for (d = 0; d < 5; d++) {
        score16x24_put(1 + (d * 2), 15, 4, d);
    }
    for (d = 5; d < 10; d++) {
        score16x24_put(1 + ((d - 5) * 2), 18, 4, d);
    }

    SSPutStr(0, 22, 1, "SSPUTDEC SIZES (1,2,3 DIGITS):");
    SSPutStr(1, 23, 1, "1-DIG:");
    SSPutDec(8, 23, 4, 7, 1);
    SSPutStr(1, 24, 1, "2-DIG:");
    SSPutDec(8, 24, 4, 42, 2);
    SSPutStr(1, 25, 1, "3-DIG:");
    SSPutDec(8, 25, 4, 255, 3);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 7: Tile Blocks & ATR Flips
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page7(void) {
    u8 t;

    SSPutStr(1, 0, 4, "PAGE 8: TILES & ATR FLIPS");

    SSPutStr(0, 2, 1, "SCFONT_PUT PAGE 0 ROWS 0-3:");
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 3, 4, 0, t, 0, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 4, 4, 0, t, 1, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 5, 4, 0, t, 2, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 6, 4, 0, t, 3, 2); }

    SSPutStr(0, 8, 1, "SCFONT_PUT PAGE 2 ROWS 0-3:");
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 9, 4, 2, t, 0, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 10, 4, 2, t, 1, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 11, 4, 2, t, 2, 2); }
    for (t = 0; t < 20; t++) { scfont_put(1 + t, 12, 4, 2, t, 3, 2); }

    SSPutStr(0, 14, 1, "ATR FLIP BITS:");
    SSPutStr(1, 15, 1, "NORMAL:");
    scfont_put(10, 15, 0x04, 0, 1, 0, 2);
    scfont_put(12, 15, 0x04, 0, 2, 0, 2);
    scfont_put(14, 15, 0x04, 0, 3, 0, 2);
    SSPutStr(1, 16, 1, "H-FLIP:");
    scfont_put(10, 16, 0x84, 0, 1, 0, 2);
    scfont_put(12, 16, 0x84, 0, 2, 0, 2);
    scfont_put(14, 16, 0x84, 0, 3, 0, 2);
    SSPutStr(1, 17, 1, "V-FLIP:");
    scfont_put(10, 17, 0x44, 0, 1, 0, 2);
    scfont_put(12, 17, 0x44, 0, 2, 0, 2);
    scfont_put(14, 17, 0x44, 0, 3, 0, 2);
    SSPutStr(1, 18, 1, "HV-FLIP:");
    scfont_put(10, 18, 0xC4, 0, 1, 0, 2);
    scfont_put(12, 18, 0xC4, 0, 2, 0, 2);
    scfont_put(14, 18, 0xC4, 0, 3, 0, 2);

    SSPutStr(0, 20, 1, "SCFONT_SQPUT (MULTI-CELL):");
    scfont_sqput(1, 21, 4, 0, 0, 0, 4, 1, 2);
    scfont_sqput(6, 21, 8, 0, 4, 0, 4, 1, 2);
    scfont_sqput(11, 21, 1, 0, 8, 0, 4, 1, 2);
    scfont_sqput(16, 21, 9, 0, 12, 0, 4, 1, 2);

    SSPutStr(0, 23, 1, "SQPUT 2-ROW BLOCK:");
    scfont_sqput(1, 24, 4, 0, 0, 0, 8, 2, 2);
    scfont_sqput(10, 24, 8, 2, 0, 0, 8, 2, 2);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 8: Health, Stun, & HUD Bars
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page8(void) {
    SSPutStr(1, 0, 4, "PAGE 9: HEALTH, STUN, HUD");

    SSPutStr(0, 2, 1, "VITAL_PUT (HP BARS Y=16-24PX):");
    vital_put(0, 8, 160, 0, 2);
    vital_put(1, 8, 100, 0, 2);

    SSPutStr(0, 4, 1, "SILVER_VITAL_PUT (RECOVERABLE):");
    silver_vital_put(0);
    silver_vital_put(1);

    SSPutStr(0, 6, 1, "VITAL_BASE_PUT (HP SHADOW):");
    vital_base_put(0);
    vital_base_put(1);

    SSPutStr(0, 8, 1, "STUN_PUT (Y=24-32PX):");
    omop_st_bar_disp[0] = 1;
    omop_st_bar_disp[1] = 1;
    stun_put(0, 100);
    stun_put(1, 60);

    SSPutStr(0, 10, 1, "STUN_BASE_PUT (STUN FRAME):");
    stun_base_put(0, 160);
    stun_base_put(1, 160);

    SSPutStr(0, 12, 1, "SPGAUGE_BASE_PUT (SA FRAME):");
    spgauge_base_put(0, 160);
    spgauge_base_put(1, 160);

    SSPutStr(0, 15, 4, "NOTE: BARS USE HARDCODED POS");
    SSPutStr(0, 16, 4, "HP: Y=16-24  STUN: Y=24-32");
    SSPutStr(0, 17, 4, "P1: X=8-168  P2: X=216-376");

    SSPutStr(0, 19, 1, "TONEDOWN (DARKEN OVERLAY):");
    ToneDown(48, 0);
}

/* ════════════════════════════════════════════════════════════════
 *  Page 9: Screen Transitions (animated)
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page9(void) {
    static u8 anim_phase = 0;

    SSPutStr(1, 0, 4, "PAGE 10: SCREEN TRANSITIONS");

    SSPutStr(0, 2, 1, "BACKGROUND TEXT FOR TRANSITIONS");
    SSPutStr(1, 4, 4, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    SSPutStr(1, 5, 4, "0123456789 THE QUICK FOX");
    SSPutStr(1, 7, 8, "THIS TEXT SHOULD APPEAR AND");
    SSPutStr(1, 8, 8, "DISAPPEAR DURING TRANSITIONS");
    SSPutStr(1, 10, 4, "ROUND 1");
    SSPutStr(1, 11, 4, "FIGHT!");
    SSPutStr(1, 14, 1, "CYCLING: FADE->WIPE VARIANTS");

    switch (anim_phase) {
    case 0:
        SSPutStr(1, 16, 4, ">> FADEOUT (BLACK)");
        if (FadeOut(0, 8, 0)) { anim_phase = 1; FadeInit(); }
        break;
    case 1:
        SSPutStr(1, 16, 4, ">> FADEIN (BLACK)");
        if (FadeIn(0, 8, 0)) { anim_phase = 2; FadeInit(); }
        break;
    case 2:
        SSPutStr(1, 16, 4, ">> FADEOUT (WHITE)");
        if (FadeOut(1, 8, 0)) { anim_phase = 3; FadeInit(); }
        break;
    case 3:
        SSPutStr(1, 16, 4, ">> FADEIN (WHITE)");
        if (FadeIn(1, 8, 0)) { anim_phase = 4; WipeInit(); }
        break;
    case 4:
        SSPutStr(1, 16, 4, ">> WIPEOUT (HORIZ)");
        if (WipeOut(0)) { anim_phase = 5; WipeInit(); }
        break;
    case 5:
        SSPutStr(1, 16, 4, ">> WIPEIN (HORIZ)");
        if (WipeIn(0)) { anim_phase = 6; WipeInit(); }
        break;
    case 6:
        SSPutStr(1, 16, 4, ">> WIPEOUT (DIAG)");
        if (WipeOut(1)) { anim_phase = 7; WipeInit(); }
        break;
    case 7:
        SSPutStr(1, 16, 4, ">> WIPEIN (DIAG)");
        if (WipeIn(1)) { anim_phase = 0; FadeInit(); }
        break;
    }
}

/* ════════════════════════════════════════════════════════════════
 *  Page 10: In-Game HUD Recreation
 * ════════════════════════════════════════════════════════════════ */
static void FontTest_Page10(void) {
    s8 rnd[] = "ROUND 1";
    s8 fgt[] = "FIGHT!";

    SSPutStr(1, 0, 4, "PAGE 11: IN-GAME HUD");

    vital_base_put(0);
    vital_base_put(1);
    vital_put(0, 8, 120, 0, 2);
    vital_put(1, 8, 90, 0, 2);

    omop_st_bar_disp[0] = 1;
    omop_st_bar_disp[1] = 1;
    stun_base_put(0, 160);
    stun_base_put(1, 160);
    stun_put(0, 80);
    stun_put(1, 40);

    SSPutStr(0, 5, 1, "TIMER DIGITS (SCFONT_SQPUT):");
    scfont_sqput(22, 0, 4, 2, 18, 2, 2, 4, 2);
    scfont_sqput(24, 0, 4, 2, 18, 2, 2, 4, 2);

    scfont_sqput(21, 1, 9, 0, 12, 6, 1, 4, 2);
    scfont_sqput(26, 1, 137, 0, 12, 6, 1, 4, 2);
    scfont_sqput(22, 4, 9, 0, 3, 18, 4, 1, 2);

    SSPutStr_Bigger(14 * 8, 8 * 8, 4, rnd, 2.0f, 0, 2);
    SSPutStr_Bigger(16 * 8, 11 * 8, 4, fgt, 2.0f, 1, 2);

    SSPutStr(0, 14, 1, "COMBO MESSAGE:");
    combo_message_set(0, 0, 2, 5, 1, 2);

    SSPutStr(0, 18, 1, "BUTTON ICONS:");
    dispButtonImage(8, 160, 2, 16, 16, 0, 0);
    dispButtonImage(32, 160, 2, 16, 16, 0, 1);
    dispButtonImage(56, 160, 2, 16, 16, 0, 2);
    dispButtonImage(80, 160, 2, 16, 16, 0, 3);

    SSPutStr(0, 22, 1, "HNC WIPE / AKAOBI:");
    SSPutStr(1, 23, 4, "ANIMATED SEQUENCES USING");
    SSPutStr(1, 24, 4, "HARDCODED FRAME TABLES");
}

/* ════════════════════════════════════════════════════════════════
 *  Main Task Dispatcher with D-pad Navigation
 * ════════════════════════════════════════════════════════════════ */
void FontTest_Task(struct _TASK* task_ptr) {
    static s16 frame_counter = 0;
    static s16 current_page = 0;
    static u16 prev_input = 0;
    u16 new_press;
    s8 page_str[8];
    u8 i;

    No_Trans = 0;
    omop_cockpit = 1;
    ppgSetupCurrentDataList(&ppgScrList);

    /* ── D-pad Navigation ──────────────────────────────────── */
    new_press = p1sw_0 & ~prev_input;
    prev_input = p1sw_0;

    if (new_press & SWK_RIGHT) {
        current_page++;
        if (current_page >= PAGE_COUNT) current_page = 0;
        frame_counter = 0;
    }
    if (new_press & SWK_LEFT) {
        current_page--;
        if (current_page < 0) current_page = PAGE_COUNT - 1;
        frame_counter = 0;
    }

    /* ── Auto-cycle ────────────────────────────────────────── */
    frame_counter++;
    if (frame_counter >= FRAMES_PER_PAGE) {
        frame_counter = 0;
        current_page++;
        if (current_page >= PAGE_COUNT) current_page = 0;
    }

    /* ── Render current page ───────────────────────────────── */
    switch (current_page) {
    case 0:  FontTest_Page0();  break;
    case 1:  FontTest_Page1();  break;
    case 2:  FontTest_Page2();  break;
    case 3:  FontTest_Page3();  break;
    case 4:  FontTest_Page4();  break;
    case 5:  FontTest_Page5();  break;
    case 6:  FontTest_Page6();  break;
    case 7:  FontTest_Page7();  break;
    case 8:  FontTest_Page8();  break;
    case 9:  FontTest_Page9();  break;
    case 10: FontTest_Page10(); break;
    }

    /* ── Page indicator bar (bottom) ───────────────────────── */
    SSPutStr(12, 27, 1, "<");
    for (i = 0; i < PAGE_COUNT; i++) {
        if (i == current_page) {
            SSPutStr(13 + i, 27, 4, "#");
        } else {
            SSPutStr(13 + i, 27, 1, ".");
        }
    }
    SSPutStr(13 + PAGE_COUNT, 27, 1, ">");

    /* Page number (handles 2-digit) */
    if (current_page + 1 >= 10) {
        page_str[0] = '1';
        page_str[1] = '0' + ((current_page + 1) - 10);
    } else {
        page_str[0] = ' ';
        page_str[1] = '0' + (current_page + 1);
    }
    page_str[2] = '/';
    page_str[3] = '1';
    page_str[4] = '0' + (PAGE_COUNT - 10);
    page_str[5] = '\0';
    SSPutStr(13 + PAGE_COUNT + 1, 27, 4, page_str);
}
