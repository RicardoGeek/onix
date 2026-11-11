//+------------------------------------------------------------------+
//|                                                        7Wave.mq5 |
//|  7Wave: the user's own rules, one step at a time.                |
//|  The exact rules are written in 7wave/RULES.md.                  |
//|                                                                  |
//|  Rule 1, the ribbon: seven EMAs of the close, 20, 40, 60, 80,    |
//|    100, 120, 140. Colors only tell the lines apart.              |
//|  Rule 2, arrows (new wave): a closed bar with                    |
//|    close > EMA20 > ... > EMA140 (UP) or the reverse (DOWN),      |
//|    unless a wave in the same direction is still going. A wave    |
//|    ends when 3 or more of the 7 lines are out of order.          |
//|  Rule 3, stars (EMA 20 crosses the ribbon): EMA 20 closes beyond |
//|    all 6 other lines after it was last beyond all of them on the |
//|    other side, while at least 3 of those 6 lines still hold the  |
//|    old trend's order.                                            |
//|  Rule 4, candle color: a star or arrow is drawn only on a bar    |
//|    that closes its color (UP bullish, DOWN bearish). Otherwise   |
//|    it waits for the first such bar, and it is cancelled if EMA   |
//|    20 stops being beyond all 6 other lines on its side first.    |
//|  Rule 5, trend filter (H1 charts): UP when the 7 lines are       |
//|    stacked up on both the last closed H4 and D1 bars, DOWN when  |
//|    both are stacked down, otherwise OFF.                         |
//|  Rule 6, swing breakout (H1 charts): with the filter UP, a buy    |
//|    stop 0.15 ATR under the nearest untouched H1 swing high aged  |
//|    12-48 bars (sell stop above the nearest swing low when DOWN). |
//|  Only closed bars are checked, so nothing repaints.              |
//+------------------------------------------------------------------+
#define WAVE_VERSION    "1.30"
#define WAVE_COUNT      7
#define ARROW_UP_CODE   233     // Wingdings arrow pointing up
#define ARROW_DOWN_CODE 234     // Wingdings arrow pointing down
#define STAR_CODE       171     // Wingdings five-pointed star
#define ARROW_GAP_PX    10      // gap in pixels between the EMA 140 line and an arrow
#define STAR_GAP_PX     24      // stars sit a little farther out, so a star never covers an arrow
//--- rules 5-6 (research/GATE_TEST.md, the SevenWave stream-A entry)
#define SETUP_SWING_BARS 3      // a swing high/low beats the 3 bars on each side of it
#define SETUP_MIN_AGE    12     // the armed pool's swing bar is 12-48 H1 bars older than the closed bar
#define SETUP_MAX_AGE    48
#define SETUP_OFFSET_ATR 0.15   // the stop entry sits this many ATR before the pool level
#define SETUP_MAX_DIST   3.0    // not armed when the entry level is more than this many ATR from the bar's open
#define SETUP_ATR_N      14     // Wilder ATR(14) of H1
#define POOL_CAP         4096   // untouched swing levels kept (gold H1 since 1998 never holds more than ~400)
#define POOL_CODE        158    // Wingdings tiny dot: the pool level
#define LEVEL_CODE       159    // Wingdings small dot: the stop-entry level
#define ENTRY_CODE       117    // Wingdings diamond: an entry
#define HUD_NAME         "7Wave_setup_status"

#property copyright   "7Wave"
#property version     WAVE_VERSION
#property description "7Wave: seven EMAs of the close (20 to 140). Arrows when the ribbon is fully aligned (new wave),"
#property description "stars when EMA 20 crosses all 6 other lines while at least 3 still hold the old order."
#property description "Both are drawn only on a bar closing their color. Only closed bars are checked."

#property indicator_chart_window
#property indicator_buffers 32
#property indicator_plots   26

//--- rule 1: default colors, picked for the black chart background
//--- (they can be changed in the indicator's Colors tab)
#property indicator_label1  "EMA 20"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'220,0,0'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "EMA 40"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'255,60,60'
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "EMA 60"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'255,130,100'
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "EMA 80"
#property indicator_type4   DRAW_LINE
#property indicator_color4  C'255,255,0'
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "EMA 100"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'150,240,100'
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

#property indicator_label6  "EMA 120"
#property indicator_type6   DRAW_LINE
#property indicator_color6  C'40,200,40'
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

#property indicator_label7  "EMA 140"
#property indicator_type7   DRAW_LINE
#property indicator_color7  C'0,140,0'
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1

//--- rule 2: arrows (colors not used by the ribbon)
#property indicator_label8  "New wave UP"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  C'0,191,255'
#property indicator_width8  2

#property indicator_label9  "New wave DOWN"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  C'255,0,255'
#property indicator_width9  2

//--- rule 3: stars (same direction colors as the arrows)
#property indicator_label10 "EMA 20 cross UP"
#property indicator_type10  DRAW_ARROW
#property indicator_color10 C'0,191,255'
#property indicator_width10 2

#property indicator_label11 "EMA 20 cross DOWN"
#property indicator_type11  DRAW_ARROW
#property indicator_color11 C'255,0,255'
#property indicator_width11 2

//--- state of every closed bar, shown only in the Data Window (blank on the bar that is still forming)
#property indicator_label12 "Aligned now (1 up, -1 down, 0 no)"
#property indicator_type12  DRAW_NONE

#property indicator_label13 "Wave (1 up, -1 down, 0 none)"
#property indicator_type13  DRAW_NONE

#property indicator_label14 "Lines out of order"
#property indicator_type14  DRAW_NONE

#property indicator_label15 "Arrow waiting for its candle (1 up, -1 down, 0 no)"
#property indicator_type15  DRAW_NONE

#property indicator_label16 "EMA 20 vs other 6 (1 above all, -1 below all, 0 inside)"
#property indicator_type16  DRAW_NONE

#property indicator_label17 "Star check"
#property indicator_type17  DRAW_NONE

#property indicator_label18 "Star waiting for its candle (1 up, -1 down, 0 no)"
#property indicator_type18  DRAW_NONE

//--- rule 6: the swing breakout setup (H1 charts), sky blue for longs and magenta for shorts
#property indicator_label19 "Swing pool for a long"
#property indicator_type19  DRAW_ARROW
#property indicator_color19 C'0,130,190'
#property indicator_width19 1

#property indicator_label20 "Buy-stop entry level"
#property indicator_type20  DRAW_ARROW
#property indicator_color20 C'0,191,255'
#property indicator_width20 1

#property indicator_label21 "Swing pool for a short"
#property indicator_type21  DRAW_ARROW
#property indicator_color21 C'190,0,190'
#property indicator_width21 1

#property indicator_label22 "Sell-stop entry level"
#property indicator_type22  DRAW_ARROW
#property indicator_color22 C'255,0,255'
#property indicator_width22 1

#property indicator_label23 "Breakout entry UP"
#property indicator_type23  DRAW_ARROW
#property indicator_color23 C'0,191,255'
#property indicator_width23 2

#property indicator_label24 "Breakout entry DOWN"
#property indicator_type24  DRAW_ARROW
#property indicator_color24 C'255,0,255'
#property indicator_width24 2

//--- rules 5-6 state, shown only in the Data Window
#property indicator_label25 "Trend filter H4+D1 (1 up, -1 down, 0 off)"
#property indicator_type25  DRAW_NONE

#property indicator_label26 "Armed pool age (H1 bars)"
#property indicator_type26  DRAW_NONE

input int InpEma1           = 20;    // EMA 1 period (fastest, red)
input int InpEma2           = 40;    // EMA 2 period (red)
input int InpEma3           = 60;    // EMA 3 period (red)
input int InpEma4           = 80;    // EMA 4 period (yellow)
input int InpEma5           = 100;   // EMA 5 period (green)
input int InpEma6           = 120;   // EMA 6 period (green)
input int InpEma7           = 140;   // EMA 7 period (slowest, green)
input int InpWaveEndLines   = 3;     // Arrows: a wave ends when this many lines are out of order (2-7)
input int InpStarMinInOrder = 3;     // Stars: at least this many of the 6 slower lines still in the old order (1-6)

//--- buffers, oldest bar at index 0
double g_ema1[], g_ema2[], g_ema3[], g_ema4[], g_ema5[], g_ema6[], g_ema7[];
double g_arrowUp[], g_arrowDown[];  // EMA 140 value on bars with an arrow, empty elsewhere
double g_starUp[], g_starDown[];    // EMA 140 value on bars with a star, empty elsewhere
double g_aligned[];       // 1 aligned UP, -1 aligned DOWN, 0 not aligned
double g_wave[];          // the wave still going after this bar (1 up, -1 down, 0 none)
double g_outOfOrder[];    // lines out of order for the wave that was going into this bar; empty when none was
double g_arrowWaiting[];  // after this bar: an arrow waiting for a candle of its color (1 up, -1 down, 0 none)
double g_ema20Side[];     // 1 EMA 20 above all 6 other lines, -1 below all 6, 0 inside the ribbon
double g_starCheck[];     // on a full-cross bar: how many of the 6 slower lines still hold the old order
double g_starWaiting[];   // after this bar: a star waiting for a candle of its color (1 up, -1 down, 0 none)
double g_lastSide[];      // where EMA 20 was last beyond all 6 other lines (1 above, -1 below, 0 not yet)
int    g_period[WAVE_COUNT];

//--- rules 5-6 buffers
double g_poolLong[], g_buyStop[];    // armed long setup of this bar: pool level and buy-stop level
double g_poolShort[], g_sellStop[];  // armed short setup of this bar: pool level and sell-stop level
double g_entryUp[], g_entryDown[];   // fill price on bars where the armed level traded
double g_filter[];                   // per closed bar: 1 / -1 / 0, the H4+D1 trend filter
double g_poolAge[];                  // age of the armed pool, in H1 bars
double g_atrH1[];                    // Wilder ATR(14) of each closed H1 bar
double g_ph[], g_phi[];              // after each closed bar: nearest untouched swing high above it, and its bar
double g_pl[], g_pli[];              // after each closed bar: nearest untouched swing low below it, and its bar

//--- rules 5-6 state, rebuilt from bar 0 on every full recalculation
double   g_shV[POOL_CAP], g_slV[POOL_CAP];   // untouched swing highs / lows
int      g_shI[POOL_CAP], g_slI[POOL_CAP];   // ... and the bars they formed on
int      g_nsh = 0, g_nsl = 0;
int      g_usedH = -1, g_usedL = -1;         // the swing bars that gave the last long / short entry
int      g_setupDone = -1;                   // last closed bar processed by rules 5-6
int      g_hintH4 = -1, g_hintD1 = -1;       // search hints into the H4 / D1 arrays
datetime g_h4T[], g_d1T[];                   // H4 / D1 bar open times
int      g_h4S[], g_d1S[];                   // H4 / D1 stack state per bar (1 up, -1 down, 0 neither)
bool     g_setupOn = false;                  // rules 5-6 run on H1 charts only

//+------------------------------------------------------------------+
int OnInit()
  {
   g_period[0] = InpEma1;
   g_period[1] = InpEma2;
   g_period[2] = InpEma3;
   g_period[3] = InpEma4;
   g_period[4] = InpEma5;
   g_period[5] = InpEma6;
   g_period[6] = InpEma7;

   for(int i = 0; i < WAVE_COUNT; i++)
     {
      if(g_period[i] < 1)
        {
         PrintFormat("7Wave: EMA %d period must be 1 or more (got %d).", i + 1, g_period[i]);
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   if(InpWaveEndLines < 2 || InpWaveEndLines > WAVE_COUNT)
     {
      PrintFormat("7Wave: the wave-end line count must be 2 to %d (got %d).", WAVE_COUNT, InpWaveEndLines);
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpStarMinInOrder < 1 || InpStarMinInOrder > WAVE_COUNT - 1)
     {
      PrintFormat("7Wave: the star in-order count must be 1 to %d (got %d).", WAVE_COUNT - 1, InpStarMinInOrder);
      return(INIT_PARAMETERS_INCORRECT);
     }

   SetIndexBuffer(0,  g_ema1,         INDICATOR_DATA);
   SetIndexBuffer(1,  g_ema2,         INDICATOR_DATA);
   SetIndexBuffer(2,  g_ema3,         INDICATOR_DATA);
   SetIndexBuffer(3,  g_ema4,         INDICATOR_DATA);
   SetIndexBuffer(4,  g_ema5,         INDICATOR_DATA);
   SetIndexBuffer(5,  g_ema6,         INDICATOR_DATA);
   SetIndexBuffer(6,  g_ema7,         INDICATOR_DATA);
   SetIndexBuffer(7,  g_arrowUp,      INDICATOR_DATA);
   SetIndexBuffer(8,  g_arrowDown,    INDICATOR_DATA);
   SetIndexBuffer(9,  g_starUp,       INDICATOR_DATA);
   SetIndexBuffer(10, g_starDown,     INDICATOR_DATA);
   SetIndexBuffer(11, g_aligned,      INDICATOR_DATA);
   SetIndexBuffer(12, g_wave,         INDICATOR_DATA);
   SetIndexBuffer(13, g_outOfOrder,   INDICATOR_DATA);
   SetIndexBuffer(14, g_arrowWaiting, INDICATOR_DATA);
   SetIndexBuffer(15, g_ema20Side,    INDICATOR_DATA);
   SetIndexBuffer(16, g_starCheck,    INDICATOR_DATA);
   SetIndexBuffer(17, g_starWaiting,  INDICATOR_DATA);
   SetIndexBuffer(18, g_poolLong,     INDICATOR_DATA);
   SetIndexBuffer(19, g_buyStop,      INDICATOR_DATA);
   SetIndexBuffer(20, g_poolShort,    INDICATOR_DATA);
   SetIndexBuffer(21, g_sellStop,     INDICATOR_DATA);
   SetIndexBuffer(22, g_entryUp,      INDICATOR_DATA);
   SetIndexBuffer(23, g_entryDown,    INDICATOR_DATA);
   SetIndexBuffer(24, g_filter,       INDICATOR_DATA);
   SetIndexBuffer(25, g_poolAge,      INDICATOR_DATA);
   SetIndexBuffer(26, g_lastSide,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(27, g_atrH1,        INDICATOR_CALCULATIONS);
   SetIndexBuffer(28, g_ph,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(29, g_phi,          INDICATOR_CALCULATIONS);
   SetIndexBuffer(30, g_pl,           INDICATOR_CALCULATIONS);
   SetIndexBuffer(31, g_pli,          INDICATOR_CALCULATIONS);

   string periods = "";
   for(int i = 0; i < WAVE_COUNT; i++)
     {
      PlotIndexSetString(i, PLOT_LABEL, "EMA " + IntegerToString(g_period[i]));
      PlotIndexSetInteger(i, PLOT_DRAW_BEGIN, g_period[i] - 1);   // hide the warm-up bars at the far left
      if(i > 0)
         periods += "/";
      periods += IntegerToString(g_period[i]);
     }

   PlotIndexSetInteger(7,  PLOT_ARROW, ARROW_UP_CODE);
   PlotIndexSetInteger(8,  PLOT_ARROW, ARROW_DOWN_CODE);
   PlotIndexSetInteger(9,  PLOT_ARROW, STAR_CODE);
   PlotIndexSetInteger(10, PLOT_ARROW, STAR_CODE);
   PlotIndexSetInteger(7,  PLOT_ARROW_SHIFT, ARROW_GAP_PX);    // UP signals below the EMA 140 line
   PlotIndexSetInteger(8,  PLOT_ARROW_SHIFT, -ARROW_GAP_PX);   // DOWN signals above it
   PlotIndexSetInteger(9,  PLOT_ARROW_SHIFT, STAR_GAP_PX);
   PlotIndexSetInteger(10, PLOT_ARROW_SHIFT, -STAR_GAP_PX);
   PlotIndexSetString(13, PLOT_LABEL, "Lines out of order (wave ends at " + IntegerToString(InpWaveEndLines) + ")");
   PlotIndexSetString(16, PLOT_LABEL, "Star check: of the 6 slower lines, still in old order (needs " +
                      IntegerToString(InpStarMinInOrder) + ")");
   PlotIndexSetInteger(18, PLOT_ARROW, POOL_CODE);
   PlotIndexSetInteger(19, PLOT_ARROW, LEVEL_CODE);
   PlotIndexSetInteger(20, PLOT_ARROW, POOL_CODE);
   PlotIndexSetInteger(21, PLOT_ARROW, LEVEL_CODE);
   PlotIndexSetInteger(22, PLOT_ARROW, ENTRY_CODE);
   PlotIndexSetInteger(23, PLOT_ARROW, ENTRY_CODE);
   for(int p = 7; p <= 25; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_setupOn = (_Period == PERIOD_H1);
   ResetSetup();
   IndicatorSetString(INDICATOR_SHORTNAME, "7Wave v" + WAVE_VERSION + " (" + periods + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectDelete(0, HUD_NAME);
  }

//+------------------------------------------------------------------+
//| Waits for the broker's H4/D1 history, then has MT5 recalculate.  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime t[];
   int      s[];
   if(LoadStacks(PERIOD_H4, t, s) && LoadStacks(PERIOD_D1, t, s))
     {
      EventKillTimer();
      ChartSetSymbolPeriod(0, _Symbol, _Period);
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2)
      return(0);

//--- rule 1: the ribbon (the forming bar's EMAs move with every tick)
   CalcEma(rates_total, prev_calculated, g_period[0], close, g_ema1);
   CalcEma(rates_total, prev_calculated, g_period[1], close, g_ema2);
   CalcEma(rates_total, prev_calculated, g_period[2], close, g_ema3);
   CalcEma(rates_total, prev_calculated, g_period[3], close, g_ema4);
   CalcEma(rates_total, prev_calculated, g_period[4], close, g_ema5);
   CalcEma(rates_total, prev_calculated, g_period[5], close, g_ema6);
   CalcEma(rates_total, prev_calculated, g_period[6], close, g_ema7);

//--- rules 2-4: checked once per bar, oldest first, when the bar has closed
   int start = prev_calculated - 1;        // the bar that was still forming at the previous call
   if(start < 1)                            // first run, or MT5 asked for a full recalculation
     {
      StartFirstBar();
      start = 1;
     }
   for(int i = start; i <= rates_total - 2; i++)
      CheckBar(i, open[i], close[i]);

//--- the bar that is still forming is never checked: no signal and no state until it closes
   ClearFormingBar(rates_total - 1);

//--- rules 5-6: the trend filter and the swing breakout (H1 charts only)
   int forming = rates_total - 1;
   if(!g_setupOn)
     {
      for(int i = MathMax(0, prev_calculated - 1); i < rates_total; i++)
         ClearSetup(i);
      UpdateHud(forming, time);
      return(rates_total);
     }
   if(prev_calculated <= 0)
      ResetSetup();                          // full recalculation: rebuild every pool and filter from bar 0
   int lastClosed = rates_total - 2;
   if(g_setupDone < lastClosed)
     {
      if(!LoadStacks(PERIOD_H4, g_h4T, g_h4S) || !LoadStacks(PERIOD_D1, g_d1T, g_d1S))
        {
         EventSetTimer(2);                   // the H4/D1 history is still loading: try again shortly
         return(0);
        }
      for(int i = g_setupDone + 1; i <= lastClosed; i++)
        {
         UpdateAtr(i, high, low, close);
         UpdatePools(i, high, low);
         g_filter[i] = FilterAt(time[i] + PeriodSeconds(PERIOD_H1));
         ArmAndTrigger(i, true, open, high, low, spread);
        }
      g_setupDone = lastClosed;
     }
//--- the forming bar shows only what was armed at its open
   g_filter[forming] = EMPTY_VALUE;
   g_atrH1[forming]  = EMPTY_VALUE;
   g_ph[forming]     = EMPTY_VALUE;
   g_phi[forming]    = -1;
   g_pl[forming]     = EMPTY_VALUE;
   g_pli[forming]    = -1;
   ArmAndTrigger(forming, false, open, high, low, spread);
   UpdateHud(forming, time);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Rules 5-6: start over from bar 0.                                |
//+------------------------------------------------------------------+
void ResetSetup()
  {
   g_nsh = 0;
   g_nsl = 0;
   g_usedH = -1;
   g_usedL = -1;
   g_setupDone = -1;
   g_hintH4 = -1;
   g_hintD1 = -1;
  }

//+------------------------------------------------------------------+
//| Rule 5: open times and stack states (1 up, -1 down, 0 neither)   |
//| of every bar of the broker's tf, with the indicator's 7 EMAs.    |
//+------------------------------------------------------------------+
bool LoadStacks(const ENUM_TIMEFRAMES tf, datetime &t[], int &s[])
  {
   int n = Bars(_Symbol, tf);
   if(n < 2)
      return(false);
   double c[];
   if(CopyTime(_Symbol, tf, 0, n, t) != n || CopyClose(_Symbol, tf, 0, n, c) != n)
      return(false);
   if(!(bool)SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED))
      return(false);
   ArrayResize(s, n);
   double e[WAVE_COUNT], k[WAVE_COUNT];
   for(int j = 0; j < WAVE_COUNT; j++)
     {
      k[j] = 2.0 / (g_period[j] + 1.0);
      e[j] = c[0];
     }
   for(int i = 0; i < n; i++)
     {
      if(i > 0)
         for(int j = 0; j < WAVE_COUNT; j++)
            e[j] = c[i] * k[j] + e[j] * (1.0 - k[j]);
      bool up = true, down = true;
      for(int j = 0; j < WAVE_COUNT - 1; j++)
        {
         if(!(e[j] > e[j + 1]))
            up = false;
         if(!(e[j] < e[j + 1]))
            down = false;
        }
      s[i] = up ? 1 : (down ? -1 : 0);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Index of the last bar of t[] (bars `sec` long) that had closed   |
//| by time tc; -1 if none. `hint` makes the in-order scan cheap.    |
//+------------------------------------------------------------------+
int LastClosed(const datetime &t[], const int sec, const datetime tc, int &hint)
  {
   int n = ArraySize(t);
   if(hint >= n)
      hint = n - 1;
   while(hint + 1 < n && t[hint + 1] + sec <= tc)
      hint++;
   while(hint >= 0 && t[hint] + sec > tc)
      hint--;
   return(hint);
  }

//+------------------------------------------------------------------+
//| Rule 5: the filter for an H1 bar that closes at time barClose.   |
//+------------------------------------------------------------------+
int FilterAt(const datetime barClose)
  {
   int k4 = LastClosed(g_h4T, PeriodSeconds(PERIOD_H4), barClose, g_hintH4);
   int kd = LastClosed(g_d1T, PeriodSeconds(PERIOD_D1), barClose, g_hintD1);
   if(k4 < 0 || kd < 0)
      return(0);
   return(g_h4S[k4] == g_d1S[kd] ? g_h4S[k4] : 0);
  }

//+------------------------------------------------------------------+
//| Rule 6: Wilder ATR(14) of closed bar i, as in the research.      |
//+------------------------------------------------------------------+
void UpdateAtr(const int i, const double &high[], const double &low[], const double &close[])
  {
   double tr = high[i] - low[i];
   if(i > 0)
      tr = MathMax(tr, MathMax(MathAbs(high[i] - close[i - 1]), MathAbs(low[i] - close[i - 1])));
   if(i < SETUP_ATR_N)
      g_atrH1[i] = (i == 0) ? tr : (g_atrH1[i - 1] * i + tr) / (i + 1);
   else
      g_atrH1[i] = g_atrH1[i - 1] + (tr - g_atrH1[i - 1]) / SETUP_ATR_N;
  }

//+------------------------------------------------------------------+
//| Rule 6: after closed bar i, add the swing high/low that bar i    |
//| confirms, drop the ones bar i traded through, and store the      |
//| nearest untouched swing high above and swing low below bar i.    |
//+------------------------------------------------------------------+
void UpdatePools(const int i, const double &high[], const double &low[])
  {
   int p = i - SETUP_SWING_BARS;
   if(p - SETUP_SWING_BARS >= 0)
     {
      bool isHigh = true, isLow = true;
      for(int q = p - SETUP_SWING_BARS; q <= p + SETUP_SWING_BARS; q++)
        {
         if(q == p)
            continue;
         if(high[q] >= high[p])
            isHigh = false;
         if(low[q] <= low[p])
            isLow = false;
        }
      if(isHigh && g_nsh < POOL_CAP)
        {
         g_shV[g_nsh] = high[p];
         g_shI[g_nsh] = p;
         g_nsh++;
        }
      if(isLow && g_nsl < POOL_CAP)
        {
         g_slV[g_nsl] = low[p];
         g_slI[g_nsl] = p;
         g_nsl++;
        }
     }
   int k = 0;
   for(int q = 0; q < g_nsh; q++)
      if(high[i] <= g_shV[q] || g_shI[q] > i - 1)
        {
         g_shV[k] = g_shV[q];
         g_shI[k] = g_shI[q];
         k++;
        }
   g_nsh = k;
   k = 0;
   for(int q = 0; q < g_nsl; q++)
      if(low[i] >= g_slV[q] || g_slI[q] > i - 1)
        {
         g_slV[k] = g_slV[q];
         g_slI[k] = g_slI[q];
         k++;
        }
   g_nsl = k;

   double best = DBL_MAX;
   int    pick = -1;
   for(int q = 0; q < g_nsh; q++)
      if(g_shV[q] > high[i] && g_shV[q] < best)
        {
         best = g_shV[q];
         pick = q;
        }
   g_ph[i]  = (pick >= 0) ? g_shV[pick] : EMPTY_VALUE;
   g_phi[i] = (pick >= 0) ? g_shI[pick] : -1;
   best = -DBL_MAX;
   pick = -1;
   for(int q = 0; q < g_nsl; q++)
      if(g_slV[q] < low[i] && g_slV[q] > best)
        {
         best = g_slV[q];
         pick = q;
        }
   g_pl[i]  = (pick >= 0) ? g_slV[pick] : EMPTY_VALUE;
   g_pli[i] = (pick >= 0) ? g_slI[pick] : -1;
  }

//+------------------------------------------------------------------+
//| Rule 6: the stop entry armed for bar i (from closed bar i-1),    |
//| and, once bar i has closed, whether it traded.                   |
//+------------------------------------------------------------------+
void ArmAndTrigger(const int i, const bool closed, const double &open[], const double &high[], const double &low[],
                   const int &spread[])
  {
   ClearSetup(i);
   int p = i - 1;
   if(p < 0 || g_filter[p] == EMPTY_VALUE || g_atrH1[p] == EMPTY_VALUE)
      return;
   int    f   = (int)g_filter[p];
   double a   = g_atrH1[p];
   double spr = spread[i] * _Point;
//--- long: a buy stop just under the nearest untouched swing high
   if(f == 1 && g_ph[p] != EMPTY_VALUE && (int)g_phi[p] != g_usedH)
     {
      int    age   = p - (int)g_phi[p];
      double level = g_ph[p] - SETUP_OFFSET_ATR * a;
      if(age >= SETUP_MIN_AGE && age <= SETUP_MAX_AGE && level - open[i] <= SETUP_MAX_DIST * a)
        {
         g_poolLong[i] = g_ph[p];
         g_buyStop[i]  = level;
         g_poolAge[i]  = age;
         if(closed && high[i] + spr >= level)
           {
            g_entryUp[i] = MathMax(level, open[i] + spr);
            g_usedH = (int)g_phi[p];
           }
        }
     }
//--- short: a sell stop just above the nearest untouched swing low
   if(f == -1 && g_pl[p] != EMPTY_VALUE && (int)g_pli[p] != g_usedL)
     {
      int    age   = p - (int)g_pli[p];
      double level = g_pl[p] + SETUP_OFFSET_ATR * a;
      if(age >= SETUP_MIN_AGE && age <= SETUP_MAX_AGE && open[i] - level <= SETUP_MAX_DIST * a)
        {
         g_poolShort[i] = g_pl[p];
         g_sellStop[i]  = level;
         g_poolAge[i]   = age;
         if(closed && low[i] <= level)
           {
            g_entryDown[i] = MathMin(level, open[i]);
            g_usedL = (int)g_pli[p];
           }
        }
     }
  }

//+------------------------------------------------------------------+
void ClearSetup(const int i)
  {
   g_poolLong[i]  = EMPTY_VALUE;
   g_buyStop[i]   = EMPTY_VALUE;
   g_poolShort[i] = EMPTY_VALUE;
   g_sellStop[i]  = EMPTY_VALUE;
   g_entryUp[i]   = EMPTY_VALUE;
   g_entryDown[i] = EMPTY_VALUE;
   g_poolAge[i]   = EMPTY_VALUE;
   if(!g_setupOn)
      g_filter[i] = EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Status line in the chart corner: the filter now and any armed    |
//| order for the bar that is forming.                               |
//+------------------------------------------------------------------+
void UpdateHud(const int forming, const datetime &time[])
  {
   string text;
   if(!g_setupOn)
      text = "7Wave swing setup (rules 5-6): open an H1 chart to see it";
   else
     {
      int p = forming - 1;
      int h4 = g_hintH4, d1 = g_hintD1;
      datetime tc = time[p] + PeriodSeconds(PERIOD_H1);
      int k4 = LastClosed(g_h4T, PeriodSeconds(PERIOD_H4), tc, h4);
      int kd = LastClosed(g_d1T, PeriodSeconds(PERIOD_D1), tc, d1);
      string s4 = (k4 < 0) ? "?" : (g_h4S[k4] == 1 ? "up" : (g_h4S[k4] == -1 ? "down" : "mixed"));
      string sd = (kd < 0) ? "?" : (g_d1S[kd] == 1 ? "up" : (g_d1S[kd] == -1 ? "down" : "mixed"));
      int f = (g_filter[p] == EMPTY_VALUE) ? 0 : (int)g_filter[p];
      text = StringFormat("7Wave filter H4+D1: %s (H4 %s, D1 %s)", f == 1 ? "UP" : (f == -1 ? "DOWN" : "OFF"), s4, sd);
      if(g_buyStop[forming] != EMPTY_VALUE)
         text += StringFormat("  |  buy stop %s under swing high %s (age %d bars)",
                              DoubleToString(g_buyStop[forming], _Digits), DoubleToString(g_poolLong[forming], _Digits),
                              (int)g_poolAge[forming]);
      else
         if(g_sellStop[forming] != EMPTY_VALUE)
            text += StringFormat("  |  sell stop %s above swing low %s (age %d bars)",
                                 DoubleToString(g_sellStop[forming], _Digits), DoubleToString(g_poolShort[forming], _Digits),
                                 (int)g_poolAge[forming]);
         else
            text += "  |  no order armed this bar";
     }
   if(ObjectFind(0, HUD_NAME) < 0)
     {
      ObjectCreate(0, HUD_NAME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_YDISTANCE, 24);
      ObjectSetString(0, HUD_NAME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, HUD_NAME, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_COLOR, C'210,210,210');
      ObjectSetInteger(0, HUD_NAME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, HUD_NAME, OBJPROP_HIDDEN, true);
     }
   ObjectSetString(0, HUD_NAME, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Rules 2-4 on closed bar i. Bar i-1 has already been checked.     |
//+------------------------------------------------------------------+
void CheckBar(const int i, const double barOpen, const double barClose)
  {
   int candle = 0;                          // 1 bullish, -1 bearish, 0 doji (neither color)
   if(barClose > barOpen)
      candle = 1;
   else
      if(barClose < barOpen)
         candle = -1;
   int side = Ema20Side(i);
   g_ema20Side[i] = side;
   ClearSignals(i);

//--- rules 2 + 4: arrows
   int wave    = StateAt(g_wave, i - 1);
   int waiting = StateAt(g_arrowWaiting, i - 1);
   g_outOfOrder[i] = EMPTY_VALUE;
   if(wave != 0)
     {
      int wrong = LinesOutOfOrder(i, wave, 0);
      g_outOfOrder[i] = wrong;
      if(wrong >= InpWaveEndLines)
         wave = 0;                          // the wave is over
     }
   if(waiting != 0)
     {
      if(side != waiting)
         waiting = 0;                       // EMA 20 is no longer beyond all 6 lines on its side: cancelled
      else
         if(candle == waiting)
           {
            DrawArrow(i, waiting);
            wave    = waiting;              // a wave starts when its arrow is drawn
            waiting = 0;
           }
     }
   int aligned = AlignmentAt(i, barClose);
   if(aligned != 0 && aligned != wave && aligned != waiting)
     {
      if(candle == aligned)
        {
         DrawArrow(i, aligned);
         wave = aligned;
        }
      else
         waiting = aligned;                 // wait for a candle of the arrow's color
     }
   g_aligned[i]      = aligned;
   g_wave[i]         = wave;
   g_arrowWaiting[i] = waiting;

//--- rules 3 + 4: stars
   int lastSide    = StateAt(g_lastSide, i - 1);
   int starWaiting = StateAt(g_starWaiting, i - 1);
   g_starCheck[i] = EMPTY_VALUE;
   if(starWaiting != 0)
     {
      if(side != starWaiting)
         starWaiting = 0;                   // EMA 20 is no longer beyond all 6 lines on its side: cancelled
      else
         if(candle == starWaiting)
           {
            DrawStar(i, starWaiting);
            starWaiting = 0;
           }
     }
   if(side != 0 && lastSide == -side)       // EMA 20 has just crossed all 6 other lines
     {
      //--- the 6 slower lines checked against the old trend's order (DOWN order for an UP cross)
      int inOrder = (WAVE_COUNT - 1) - LinesOutOfOrder(i, -side, 1);
      g_starCheck[i] = inOrder;
      if(inOrder >= InpStarMinInOrder)
        {
         if(candle == side)
            DrawStar(i, side);
         else
            starWaiting = side;             // wait for a candle of the star's color
        }
     }
   if(side != 0)
      lastSide = side;
   g_lastSide[i]    = lastSide;
   g_starWaiting[i] = starWaiting;
  }

//+------------------------------------------------------------------+
//|  1: close > EMA20 > EMA40 > EMA60 > EMA80 > EMA100 > EMA120 > EMA140
//| -1: close < EMA20 < EMA40 < EMA60 < EMA80 < EMA100 < EMA120 < EMA140
//|  0: anything else                                                |
//+------------------------------------------------------------------+
int AlignmentAt(const int i, const double barClose)
  {
   if(barClose > g_ema1[i] && g_ema1[i] > g_ema2[i] && g_ema2[i] > g_ema3[i] && g_ema3[i] > g_ema4[i] &&
      g_ema4[i] > g_ema5[i] && g_ema5[i] > g_ema6[i] && g_ema6[i] > g_ema7[i])
      return(1);
   if(barClose < g_ema1[i] && g_ema1[i] < g_ema2[i] && g_ema2[i] < g_ema3[i] && g_ema3[i] < g_ema4[i] &&
      g_ema4[i] < g_ema5[i] && g_ema5[i] < g_ema6[i] && g_ema6[i] < g_ema7[i])
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| 1: EMA 20 above all 6 other lines, -1: below all 6, 0: inside.   |
//+------------------------------------------------------------------+
int Ema20Side(const int i)
  {
   double f = g_ema1[i];
   if(f > g_ema2[i] && f > g_ema3[i] && f > g_ema4[i] && f > g_ema5[i] && f > g_ema6[i] && f > g_ema7[i])
      return(1);
   if(f < g_ema2[i] && f < g_ema3[i] && f < g_ema4[i] && f < g_ema5[i] && f < g_ema6[i] && f < g_ema7[i])
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| How many lines, from line `first` (0 = EMA 20, 1 = EMA 40) to    |
//| EMA 140, are out of order on bar i for direction dir (1 up,      |
//| -1 down). A line is out of order when it is on the wrong side of |
//| at least one other line of that set: going UP every faster EMA   |
//| must be above every slower one, going DOWN below it.             |
//| UP examples: EMA 20 under EMA 40 -> 2 lines (20, 40);            |
//| EMA 20 under EMA 40 and EMA 60 -> 3 lines (20, 40, 60).          |
//+------------------------------------------------------------------+
int LinesOutOfOrder(const int i, const int dir, const int first)
  {
   double v[WAVE_COUNT];
   v[0] = g_ema1[i];
   v[1] = g_ema2[i];
   v[2] = g_ema3[i];
   v[3] = g_ema4[i];
   v[4] = g_ema5[i];
   v[5] = g_ema6[i];
   v[6] = g_ema7[i];

   int wrong[WAVE_COUNT];
   ArrayInitialize(wrong, 0);
   for(int a = first; a < WAVE_COUNT - 1; a++)      // a is the faster line of each pair
      for(int b = a + 1; b < WAVE_COUNT; b++)
        {
         bool inOrder = (dir > 0) ? (v[a] > v[b]) : (v[a] < v[b]);
         if(!inOrder)
           {
            wrong[a] = 1;
            wrong[b] = 1;
           }
        }

   int count = 0;
   for(int k = first; k < WAVE_COUNT; k++)
      count += wrong[k];
   return(count);
  }

//+------------------------------------------------------------------+
int StateAt(const double &buffer[], const int i)
  {
   return((buffer[i] == EMPTY_VALUE) ? 0 : (int)buffer[i]);
  }

//+------------------------------------------------------------------+
void DrawArrow(const int i, const int dir)
  {
   if(dir > 0)
      g_arrowUp[i] = g_ema7[i];
   else
      g_arrowDown[i] = g_ema7[i];
  }

//+------------------------------------------------------------------+
void DrawStar(const int i, const int dir)
  {
   if(dir > 0)
      g_starUp[i] = g_ema7[i];
   else
      g_starDown[i] = g_ema7[i];
  }

//+------------------------------------------------------------------+
void ClearSignals(const int i)
  {
   g_arrowUp[i]   = EMPTY_VALUE;
   g_arrowDown[i] = EMPTY_VALUE;
   g_starUp[i]    = EMPTY_VALUE;
   g_starDown[i]  = EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Bar 0 has no bar before it: no signal, nothing going on yet.     |
//+------------------------------------------------------------------+
void StartFirstBar()
  {
   ClearSignals(0);
   g_aligned[0]      = 0;
   g_wave[0]         = 0;
   g_outOfOrder[0]   = EMPTY_VALUE;
   g_arrowWaiting[0] = 0;
   g_ema20Side[0]    = Ema20Side(0);
   g_starCheck[0]    = EMPTY_VALUE;
   g_starWaiting[0]  = 0;
   g_lastSide[0]     = 0;
  }

//+------------------------------------------------------------------+
void ClearFormingBar(const int i)
  {
   ClearSignals(i);
   g_aligned[i]      = EMPTY_VALUE;
   g_wave[i]         = EMPTY_VALUE;
   g_outOfOrder[i]   = EMPTY_VALUE;
   g_arrowWaiting[i] = EMPTY_VALUE;
   g_ema20Side[i]    = EMPTY_VALUE;
   g_starCheck[i]    = EMPTY_VALUE;
   g_starWaiting[i]  = EMPTY_VALUE;
   g_lastSide[i]     = EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Exponential moving average of the close, with the EMA formula of |
//| MetaTrader's built-in Moving Average (Exponential):              |
//|   k      = 2 / (period + 1)                                      |
//|   EMA[0] = close[0]                        (oldest bar)          |
//|   EMA[i] = close[i] * k + EMA[i-1] * (1 - k)                     |
//| On each tick only the forming bar and any new bars are redone.   |
//+------------------------------------------------------------------+
void CalcEma(const int rates_total, const int prev_calculated, const int period,
             const double &price[], double &ema[])
  {
   double k     = 2.0 / (period + 1.0);
   int    start = prev_calculated - 1;     // the bar that was still forming last time

   if(start < 1)                            // first run, or MT5 asked for a full recalculation
     {
      ema[0] = price[0];
      start  = 1;
     }
   for(int i = start; i < rates_total; i++)
      ema[i] = price[i] * k + ema[i - 1] * (1.0 - k);
  }
//+------------------------------------------------------------------+
