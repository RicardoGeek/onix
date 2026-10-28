//+------------------------------------------------------------------+
//|                                       aegis_regime_hunter_ea.mq5 |
//|                                  Copyright 2026, Goldie Service |
//|                                      https://github.com/goldie  |
//+------------------------------------------------------------------+
//| Changelog                                                        |
//|  4.00  High-Velocity Prop & Multi-Stage Ratchet Upgrade:         |
//|        1. Two-Zone Prop Risk Governor + Anti-Zeno min-lot        |
//|           recovery (fixes 2024 285-trade drawdown lockout).      |
//|        2. Multi-stage R-ratchet (+1.00R -> 30% partial + +0.12R  |
//|           BE lock, unlocking Unit 2 pyramid 40% earlier; +1.75R  |
//|           -> +0.70R lock; +2.80R -> +1.60R lock + dynamic ATR).  |
//|        3. London Open (07:00 UTC) range breakout module alongside|
//|           13:00 UTC NY Data-Hour breakout + 21:00-01:00 UTC      |
//|           rollover dead-zone & candle-body conviction filter.    |
//|        4. Configurable prop daily reset anchor (InpPropDayAnchor)|
//|           and zero sub-2-minute hold guarantee on fill slippage. |
//|  3.53  Saved state stays with the account it belongs to: the     |
//|        login is remembered at start-up. Switching accounts with  |
//|        the EA attached used to save the old account's peak and   |
//|        floors under the NEW login (MT5 already reports the new   |
//|        login while the EA shuts down), so a funded account could |
//|        inherit the challenge's equity peak. Flatten requests     |
//|        that cannot work (AutoTrading OFF, e.g. the local copy of |
//|        a VPS-hosted EA) no longer fire orders on every tick, and |
//|        repeated FLATTEN lines are logged at most once a minute.  |
//|  3.52  SL/TP re-anchored to the actual fill: an entry that fills |
//|        far from the requested price (news spike, execution       |
//|        delay) can no longer lose more than its planned risk.     |
//|        Ported from Bollinger Retrace v9.21.                      |
//|  3.51  Money-per-point fallback takes the larger of tick value   |
//|        and contract size (Upcomers XAUUSD reports TickValue 0.10 |
//|        with Contract 100); only used if the broker's own profit  |
//|        calculation fails. Journal shows what 1 lot makes per     |
//|        1.00 of price, by each method, and the start-up line      |
//|        shows the challenge target.                               |
//|  3.50  Prop firm rules (checked against Upcomers): challenge     |
//|        target input banks the target flat and stops (targets     |
//|        count closed balance with no open positions); one trade   |
//|        idea never risks > 1.5% of the initial balance (3% single-|
//|        trade rule); the EA's own exits wait 2 minutes (tick-     |
//|        scalping rule); [PROP AUDIT] adds sub-2-minute trades and |
//|        the worst trade-idea loss.                                |
//|  3.41  Prop start-up safety: saved state keyed by account (a     |
//|        terminal reused across accounts cannot hand over another  |
//|        account's floors); starting balance = the account's first |
//|        deposit and day bases = the real start-of-day balance,    |
//|        both from history, so attaching late cannot loosen the    |
//|        firm's limits. Daily 3% taken from the smaller of the day |
//|        base and the initial balance (both firm conventions).     |
//|        [PROP AUDIT] line: closest approach to the real 3% daily  |
//|        (4 reset times) and 6% trailing limits.                   |
//|  3.40  Broker clock read from gold's daily reopen (18:00 New     |
//|        York; 1221 of 1223 reopens 2022-2026, DST included) plus  |
//|        the US DST calendar: exact UTC on any broker, live and in |
//|        the tester, no settings. Removed InpServerGmtOffset,      |
//|        InpDayResetHour and InpWeekendFlatHour. Prop daily floor  |
//|        now uses the strictest of the four common reset times     |
//|        (server midnight, 17:00 NY, 00:00 UTC, 00:00 CE(S)T).      |
//|        Weekend flat closes 1h before the Friday close. Session   |
//|        module back on by default (MT5, Pepperstone: personal     |
//|        2024-26 +$335k vs +$247k without; prop 2025-26 +$85k vs   |
//|        +$70k). The any-firm daily floor costs ~7% in prop mode.  |
//|  3.30  Session module off by default and only with a manual     |
//|        GMT offset: bar-shape clock detection proved unreliable   |
//|        (an hour off around US daylight saving). Core strategy    |
//|        needs no clock. Removed the daily offset flip-flop.       |
//|  3.20  Prop: open trades' giveback kept inside the daily room    |
//|        (start-of-day equity includes floating profit; a runner   |
//|        giving it back counted as a daily loss and could breach). |
//|  3.10  Clock read from broker bars; spread-spike entry guard.    |
//|  3.00  Auto GMT offset. 2.90 NY session module. 2.80 trail lock. |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Goldie Service"
#property link      "https://github.com/goldie"
#property version   "4.00"
#property description "Aegis v4.00 - XAUUSD H4-trend-aligned 12h + London/NY range breakout with multi-stage R-ratchet."
#property description "Research: Dukascopy & Pepperstone Real-Tick M15 2024-2026."
#property description "Hard SL 3 ATR + TP 8R + Stage-1 Partial/BE (+1.0R) + Chandelier trail. 2nd unit once 1st is risk-free."
#property description "Prop mode: 3% daily / 6% trailing floors with Two-Zone Risk Governor & Anti-Zeno min-lot recovery."
#property description "Risk budget is account-wide: safe to run on two symbols (use a different magic number per chart)."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Strategy constants (validated on 2022-2026 XAUUSD data).         |
//| Change only together with a new backtest.                        |
//+------------------------------------------------------------------+
const ENUM_TIMEFRAMES EXEC_TF            = PERIOD_M15;  // execution timeframe (chart timeframe is ignored)
const int             CHANNEL_HOURS      = 12;          // breakout channel length (12h: more trades AND better returns than 24h)
const int             ATR_PERIOD         = 14;
const double          SL_ATR             = 3.0;         // initial stop distance (x M15 ATR)
const double          InpMinStopAtr      = 0.8;         // floor for a session-range stop (x M15 ATR)
const double          TRAIL_ATR          = 5.0;         // chandelier trail distance (x M15 ATR)
const double          TP_R               = 8.0;         // take profit (R multiple)
const ENUM_TIMEFRAMES TREND_TF           = PERIOD_H4;   // trend filter timeframe (warms up in ~9 days)
const int             TREND_FAST_EMA     = 20;
const int             TREND_SLOW_EMA     = 50;
const double          TREND_MAX_STRETCH  = 6.0;         // skip entries this many trend-ATRs away from the slow EMA
const double          MAX_SPREAD_ATR     = 0.15;        // hard backstop: skip entries while spread > 15% of M15 ATR
const int             LON_RANGE_HOUR_UTC = 7;           // London Open range hour (07:00-08:00 UTC)
const int             NY_RANGE_HOUR_UTC  = 13;          // US data hour: gold's most volatile hour in every year 2022-2026
const double          SPREAD_SPIKE_MULT  = 2.5;         // block entries while spread > this x its own median
const int             SPREAD_SAMPLES     = 96;          // rolling spread window (1 day of M15 bars)
const double          PROP_DAILY_PCT     = 3.0;
const double          PROP_TRAIL_PCT     = 6.0;
const double          PROP_BUFFER_PCT    = 0.5;         // internal floors sit this far above the real limits
const double          ROOM_DIVISOR       = 4.0;         // legacy divisor reference
const double          OPEN_RISK_FRACTION = 0.9;         // prop: open trades may give back at most 90% of the room left
const double          PERSONAL_DAY_STOP  = 5.0;         // personal: no new entries after a 5% losing day
const int             MIN_TREND_BARS     = 60;          // trend EMAs need this much history to be trusted
const double          AGGR_MAX_RISK      = 3.0;         // Aggressive profile: risk at the balance high-water mark
const double          AGGR_MIN_RISK      = 0.75;        // ...shrinking linearly to this...
const double          AGGR_DD_SPAN       = 15.0;        // ...as the drawdown from the high-water mark reaches 15%
const double          MAX_PROFILE_RISK   = 3.0;         // Maximum profile: flat 3% (backtest max drawdown 57%)
const int             REOPEN_NY_HOUR     = 18;          // gold reopens after its daily/weekend break at 18:00 New York
const int             BREAK_MIN_GAP      = 45 * 60;     // a hole in the bars this long (seconds) is a market break
const int             CLOCK_VOTES        = 5;           // recent reopens used to read the broker's clock
const int             WEEKEND_FLAT_NY    = 16;          // weekend flat: Friday 16:00 New York, 1h before the close
const double          PROP_MAX_IDEA_PCT  = 1.5;         // prop: one trade idea never risks more than 1.5% of the initial balance
const double          TARGET_CUSHION_PCT = 0.10;        // bank the challenge target this far above it (closing costs)
const int             MIN_HOLD_SEC       = 120;         // the EA's own exits wait 2 minutes (firms flag sub-2-minute trades)

// Daily-loss reset times used by prop firms. The EA keeps a day base for each and
// enforces the selected convention (or all four when ANCHOR_ALL_STRICTEST is chosen).
enum ENUM_DAY_ANCHOR
{
   ANCHOR_ALL_STRICTEST = -1, // strictest of all 4 reset times simultaneously
   ANCHOR_SERVER = 0,         // broker server midnight (Pepperstone, Upcomers, GetLeveraged)
   ANCHOR_NY17,               // 17:00 New York (the forex day)
   ANCHOR_UTC,                // 00:00 UTC
   ANCHOR_CET,                // 00:00 Central European (FTMO-style)
   ANCHOR_COUNT
};

enum ENUM_RISK_PROFILE
{
   PROFILE_STEADY = 0,     // Steady: 1% per trade (backtest max DD 23%)
   PROFILE_AGGRESSIVE,     // Aggressive: 3% at highs -> 0.75% in drawdown (max DD 24%)
   PROFILE_MAXIMUM,        // Maximum: 3% flat (max DD 57%)
   PROFILE_CUSTOM          // Custom: use the Custom Risk % input
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Account & Risk ==="
input bool                 InpIsPropFirm           = false;            // is_prop_firm (true = 3% daily / 6% trailing DD rules)
input ENUM_RISK_PROFILE    InpRiskProfile          = PROFILE_STEADY;   // Risk profile (personal mode)
input double               InpRiskPercent          = 1.0;              // Custom risk per trade % (profile = Custom)
input double               InpPropRiskPercent      = 0.90;             // Risk per trade % of equity (prop mode; v4.00 velocity default)
input double               InpInitialBalance       = 0.0;              // Prop: challenge starting balance (0 = auto-detect)
input int                  InpMaxUnits             = 2;                // Max units per trend (extra units only once the first is risk-free)
input double               InpMaxMinLotRiskPct     = 5.0;              // Small accounts: accept min lot if it risks <= this % (personal)

input group "=== London & New York Session Modules ==="
input bool                 InpUseLondonSession     = true;             // London Open hour (07:00 UTC) range breakouts
input int                  InpLonWindowHours       = 3;                // Hours after London range in which a breakout still counts
input bool                 InpUseNySession         = true;             // US data hour (13:00 UTC) range breakouts; broker clock is automatic
input int                  InpNyWindowHours        = 4;                // Hours after NY range in which a breakout still counts

input group "=== Prop Firm House Rules ==="
input ENUM_DAY_ANCHOR      InpPropDayAnchor        = ANCHOR_ALL_STRICTEST;    // Prop daily reset clock (ANCHOR_SERVER or ANCHOR_ALL_STRICTEST)
input bool                 InpTrailLocksAtStart    = true;             // Firm's trailing DD freezes at the starting balance (set false if it trails forever)
input bool                 InpWeekendFlat          = false;            // Close everything 1h before the Friday close (only if the firm requires it)
input double               InpPropTargetPct        = 0.0;              // Challenge profit target % (e.g. 5): bank it flat and stop. 0 = funded / no target

input group "=== General ==="
input long                 InpMagicNumber          = 555400;           // Magic Number
input bool                 InpShowHUD              = true;             // Show On-Chart Info Panel

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade                     g_trade;
ENUM_ORDER_TYPE_FILLING    g_filling        = ORDER_FILLING_IOC;
bool                       g_is_netting     = false;

int                        h_atr            = INVALID_HANDLE;
int                        h_tr_fast        = INVALID_HANDLE;
int                        h_tr_slow        = INVALID_HANDLE;
int                        h_tr_atr         = INVALID_HANDLE;

int                        g_channel_bars   = 96;
int                        g_srv_minus_ny   = 0;     // broker server time minus New York time, in hours
bool                       g_clock_known    = false; // set once a gold reopen has been seen in the bars
int                        g_clock_votes    = 0;     // how many recent reopens agreed
int                        g_last_utc_off   = 99;    // last logged server UTC offset (log on change only)
int                        g_clock_changes  = 0;
double                     g_spread_hist[];          // rolling spread samples
int                        g_spread_pos     = 0;
int                        g_spread_count   = 0;
datetime                   g_last_bar       = 0;

// A breakout signal stays valid for its entry bar (waits out a wide spread)
int                        g_signal_dir     = 0;
double                     g_signal_sl      = 0.0;
bool                       g_signal_is_ny   = false;
bool                       g_signal_is_lon  = false;
ulong                      g_partial_ids[];
datetime                   g_signal_bar     = 0;
bool                       g_signal_logged  = false;

// Guard state (persisted so a restart never resets the prop limits)
double                     g_init_balance   = 0.0;
double                     g_peak_equity    = 0.0;
datetime                   g_day_start      = 0;
double                     g_day_base       = 0.0;   // server-midnight base (HUD, personal day stop)
long                       g_anchor_day[ANCHOR_COUNT];      // current day of each reset anchor
double                     g_anchor_base[ANCHOR_COUNT];     // max(balance, equity) when that day began
datetime                   g_anchor_since[ANCHOR_COUNT];    // server time the anchor's day began
datetime                   g_halt_until     = 0;
string                     g_halt_reason    = "";
double                     g_peak_balance   = 0.0;   // closed-balance high-water mark (Aggressive profile)

// Diagnostics (printed as one [SUMMARY] line when the EA stops)
int                        g_sig_long       = 0;
int                        g_sig_short      = 0;
int                        g_entry_long     = 0;
int                        g_entry_short    = 0;
int                        g_warmup_bars    = 0;
double                     g_audit_day[ANCHOR_COUNT];       // worst equity vs day base, %, per reset convention
datetime                   g_audit_day_t[ANCHOR_COUNT];
double                     g_audit_trail    = 1e9;          // least room above the real trailing floor, % of start
datetime                   g_audit_trail_t  = 0;
datetime                   g_start_time     = 0;            // account start (first deposit) for the target report
long                       g_login          = 0;            // account the saved state belongs to (set at start-up)
string                     g_flatten_key    = "";           // last FLATTEN reason logged (repeat-log throttle)
datetime                   g_flatten_t      = 0;
bool                       g_target_done    = false;
string                     g_skip_keys[];
int                        g_skip_counts[];
double                     g_month_closed   = 0.0;

// HUD snapshot
int                        g_trend          = 0;
double                     g_atr_value      = 0.0;
double                     g_channel_hi     = 0.0;
double                     g_channel_lo     = 0.0;
double                     g_stretch        = 0.0;
string                     g_last_event     = "Waiting for the first closed bar";
uint                       g_last_hud_ms    = 0;

//+------------------------------------------------------------------+
//| Broker clock, read from the market itself                        |
//| Gold halts every day 17:00-18:00 New York time (CME maintenance) |
//| and over the weekend, and always reopens at 18:00 New York:      |
//| 1221 of 1223 breaks in 2022-2026, daylight saving included (the  |
//| other 2 were mid-session data holes). So the server hour of the  |
//| first bar after a break, minus 18, is the server's offset from   |
//| New York, and the US DST calendar turns that into an exact UTC   |
//| offset. Same method live and in the Strategy Tester (where       |
//| TimeGMT() is meaningless), on any broker, with no settings.      |
//| Re-read at every reopen, so a broker DST change shows up at once.|
//+------------------------------------------------------------------+
datetime MakeTime(const int year, const int mon, const int day, const int hour)
{
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year;
   dt.mon  = mon;
   dt.day  = day;
   dt.hour = hour;
   return StructToTime(dt);
}

int DayOfNthSunday(const int year, const int mon, const int nth)
{
   MqlDateTime dt;
   TimeToStruct(MakeTime(year, mon, 1, 0), dt);
   return 1 + (7 - dt.day_of_week) % 7 + 7 * (nth - 1);
}

// Last Sunday of March or October (both have 31 days)
int DayOfLastSunday(const int year, const int mon)
{
   int d = DayOfNthSunday(year, mon, 4);
   return (d + 7 <= 31) ? d + 7 : d;
}

// US daylight saving on New York wall-clock time: 2nd Sunday of March 02:00 to 1st Sunday of November 02:00
bool UsDst(const datetime ny_local)
{
   MqlDateTime dt;
   TimeToStruct(ny_local, dt);
   return (ny_local >= MakeTime(dt.year, 3, DayOfNthSunday(dt.year, 3, 2), 2) &&
           ny_local <  MakeTime(dt.year, 11, DayOfNthSunday(dt.year, 11, 1), 2));
}

// EU summer time on UTC: last Sunday of March 01:00 to last Sunday of October 01:00
bool EuDst(const datetime utc)
{
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   return (utc >= MakeTime(dt.year, 3, DayOfLastSunday(dt.year, 3), 1) &&
           utc <  MakeTime(dt.year, 10, DayOfLastSunday(dt.year, 10), 1));
}

datetime ServerToNy(const datetime t)
{
   return (datetime)((long)t - (long)g_srv_minus_ny * 3600);
}

// Server time minus UTC, in hours, at server time t
int ServerUtcOffset(const datetime t)
{
   return g_srv_minus_ny + (UsDst(ServerToNy(t)) ? -4 : -5);
}

datetime ServerToUtc(const datetime t)
{
   return (datetime)((long)t - (long)ServerUtcOffset(t) * 3600);
}

// Server hour holding the US data hour (13:00 UTC) today
int SessionHourServer()
{
   return ((NY_RANGE_HOUR_UTC + ServerUtcOffset(TimeCurrent())) % 24 + 24) % 24;
}

// Server hour holding the London Open hour (07:00 UTC) today
int LondonHourServer()
{
   return ((LON_RANGE_HOUR_UTC + ServerUtcOffset(TimeCurrent())) % 24 + 24) % 24;
}

bool IsPartialDone(const ulong pos_id)
{
   int n = ArraySize(g_partial_ids);
   for(int i = 0; i < n; i++)
      if(g_partial_ids[i] == pos_id) return true;
   return false;
}

void MarkPartialDone(const ulong pos_id)
{
   if(IsPartialDone(pos_id)) return;
   int n = ArraySize(g_partial_ids);
   ArrayResize(g_partial_ids, n + 1);
   g_partial_ids[n] = pos_id;
}

// Server hours (and times) of the most recent reopens after a market break, newest first
int RecentReopens(int &hours[], datetime &times[])
{
   ArrayResize(hours, 0);
   ArrayResize(times, 0);
   MqlRates r[];
   int n = CopyRates(_Symbol, EXEC_TF, 0, 96 * 21, r);      // three weeks, oldest first
   for(int i = n - 1; i >= 1 && ArraySize(hours) < CLOCK_VOTES; i--)
   {
      if((long)r[i].time - (long)r[i - 1].time < BREAK_MIN_GAP) continue;
      MqlDateTime dt;
      TimeToStruct(r[i].time, dt);
      int k = ArraySize(hours);
      ArrayResize(hours, k + 1);
      ArrayResize(times, k + 1);
      hours[k] = dt.hour;
      times[k] = r[i].time;
   }
   return ArraySize(hours);
}

int NormHours(const int h)
{
   return ((h + 12) % 24 + 24) % 24 - 12;
}

// True when the move between two reopens is exactly a daylight-saving switch: either New York
// moved and the broker's UTC offset did not (fixed-offset brokers), or the broker follows EU
// summer time and an EU switch happened in between. Such a move is real: accept it at once.
bool DstExplains(const int h_old, const datetime t_old, const int h_new, const datetime t_new)
{
   int s_old = NormHours(h_old - REOPEN_NY_HOUR);
   int s_new = NormHours(h_new - REOPEN_NY_HOUR);
   int u_old = s_old + (UsDst((datetime)((long)t_old - (long)s_old * 3600)) ? -4 : -5);
   int u_new = s_new + (UsDst((datetime)((long)t_new - (long)s_new * 3600)) ? -4 : -5);
   if(u_new == u_old) return true;
   bool eu_old = EuDst((datetime)((long)t_old - (long)u_old * 3600));
   bool eu_new = EuDst((datetime)((long)t_new - (long)u_new * 3600));
   return (eu_old != eu_new && u_new - u_old == (eu_new ? 1 : -1));
}

// Reads the clock from the recent reopens. Returns true once the clock is known.
bool RefreshBrokerClock()
{
   int      hours[];
   datetime times[];
   int n = RecentReopens(hours, times);
   if(n < 1) return g_clock_known;

   // Majority of the recent reopens, so a single data hole cannot move the clock. The newest
   // wins at once when the one before agrees or a DST switch explains the move exactly.
   // Replayed on six broker conventions 2022-2026: right on 1220 of 1220 days for each.
   int best = hours[0];
   int best_cnt = 0;
   for(int i = 0; i < n; i++)
   {
      int cnt = 0;
      for(int j = 0; j < n; j++)
         if(hours[j] == hours[i]) cnt++;
      if(cnt > best_cnt) { best_cnt = cnt; best = hours[i]; }
   }
   bool take_newest = (n >= 2 && (hours[0] == hours[1] || DstExplains(hours[1], times[1], hours[0], times[0])));
   int  hour  = take_newest ? hours[0] : best;
   int  votes = 0;
   for(int i = 0; i < n; i++)
      if(hours[i] == hour) votes++;

   bool first     = !g_clock_known;
   g_srv_minus_ny = NormHours(hour - REOPEN_NY_HOUR);
   g_clock_votes  = votes;
   g_clock_known  = true;

   int off = ServerUtcOffset(TimeCurrent());
   if(off != g_last_utc_off)
   {
      if(!first) g_clock_changes++;
      string check = "";
      if(!MQLInfoInteger(MQL_TESTER))
      {
         int term = (int)MathRound((double)((long)TimeTradeServer() - (long)TimeGMT()) / 3600.0);
         check = (term == off) ? " | terminal clock agrees"
                               : StringFormat(" | terminal clock says UTC%+d (the bars win)", term);
      }
      string why = (take_newest && hours[0] != hours[1]) ? "a daylight-saving switch explains the move"
                                                         : StringFormat("%d of %d recent breaks agree", votes, n);
      PrintFormat("--> [CLOCK] %s: server = New York %+dh = UTC%+d (gold reopens %02d:00 server, %s) | US data hour %02d:00 server%s",
                  first ? "Read from the broker's bars" : "Changed", g_srv_minus_ny, off, hour, why,
                  SessionHourServer(), check);
      g_last_utc_off = off;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRiskPercent <= 0.0 || InpPropRiskPercent <= 0.0 || InpMaxUnits < 1)
   {
      Print("--> [INIT ERROR] Risk % must be > 0 and Max Units must be >= 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   g_trade.SetDeviationInPoints(50);
   g_filling = DetectFilling();
   g_trade.SetTypeFilling(g_filling);
   g_is_netting = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   h_atr     = iATR(_Symbol, EXEC_TF, ATR_PERIOD);
   h_tr_fast = iMA(_Symbol, TREND_TF, TREND_FAST_EMA, 0, MODE_EMA, PRICE_CLOSE);
   h_tr_slow = iMA(_Symbol, TREND_TF, TREND_SLOW_EMA, 0, MODE_EMA, PRICE_CLOSE);
   h_tr_atr  = iATR(_Symbol, TREND_TF, ATR_PERIOD);
   if(h_atr == INVALID_HANDLE || h_tr_fast == INVALID_HANDLE || h_tr_slow == INVALID_HANDLE || h_tr_atr == INVALID_HANDLE)
   {
      PrintFormat("--> [INIT ERROR] Failed to create indicator handles. Error: %d", GetLastError());
      return INIT_FAILED;
   }

   g_channel_bars = (int)MathMax(10.0, (double)(CHANNEL_HOURS * 3600) / (double)PeriodSeconds(EXEC_TF));

   ArrayInitialize(g_anchor_day, -1);
   ArrayInitialize(g_anchor_base, 0.0);
   ArrayInitialize(g_anchor_since, 0);
   ArrayInitialize(g_audit_day, 0.0);
   ArrayInitialize(g_audit_day_t, 0);
   g_login = AccountInfoInteger(ACCOUNT_LOGIN);
   LoadState();

   // Never act on a breakout that closed before the EA was attached
   g_last_bar = iTime(_Symbol, EXEC_TF, 0);

   PrintFormat("Aegis v3.53 initialized on %s | Mode: %s | Risk now: %.2f%% | Max units: %d | Magic: %I64d | %s",
               _Symbol,
               InpIsPropFirm ? StringFormat("PROP (%.1f%% daily / %.1f%% trailing on %.2f, %s)", PROP_DAILY_PCT, PROP_TRAIL_PCT, g_init_balance,
                                            InpPropTargetPct > 0.0 ? StringFormat("challenge target +%.1f%% = %.2f", InpPropTargetPct,
                                                                                  g_init_balance * (1.0 + InpPropTargetPct / 100.0))
                                                                   : "no target: funded account") : "PERSONAL",
               ProfileRiskPercent(), InpMaxUnits, InpMagicNumber,
               g_is_netting ? "NETTING account (1 unit max)" : "HEDGING account");

   if(!RefreshBrokerClock())
      Print("--> [CLOCK] No market break in the recent bars yet: the clock is read at the next gold reopen. "
            "Until then prop floors use server midnight and the session module waits.");

   PrintFormat("--> [BROKER SPECS: %s] Digits=%d, Point=%.5f, TickSize=%.5f, TickValue=%.5f, Contract=%.2f, StopsLevel=%d, MinLot=%.2f, Step=%.2f",
               _Symbol, _Digits, _Point,
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));

   // What one lot really makes or loses per 1.00 of price, by the broker's own profit formula (the one
   // position sizing uses), next to what the tick value and contract size would each claim
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(px <= 0.0) px = iClose(_Symbol, EXEC_TF, 0);
   double per_point = 0.0;
   bool   calc_ok   = (px > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, px, px + 1.0, per_point));
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   PrintFormat("--> [BROKER SPECS: %s] A 1.00 price move on 1.00 lot = %s by the broker's profit formula "
               "(used for sizing) | tick value implies %.2f | contract size implies %.2f",
               _Symbol, calc_ok ? StringFormat("%.2f %s", per_point, AccountInfoString(ACCOUNT_CURRENCY)) : "unavailable (no quote yet)",
               (tick_size > 0.0) ? SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / tick_size : 0.0,
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string skips = "";
   for(int i = 0; i < ArraySize(g_skip_keys); i++)
      skips += StringFormat("%s%s=%d", (i > 0) ? ", " : "", g_skip_keys[i], g_skip_counts[i]);
   PrintFormat("--> [SUMMARY] Signals long/short: %d/%d | Entries long/short: %d/%d | Warm-up bars (no daily trend): %d | Skipped: %s | Clock: %s",
               g_sig_long, g_sig_short, g_entry_long, g_entry_short, g_warmup_bars, (skips == "") ? "none" : skips,
               g_clock_known ? StringFormat("server = New York %+dh, %d UTC offset changes", g_srv_minus_ny, g_clock_changes) : "never read");
   PrintFormat("--> [PROP AUDIT] %s", AuditLine());
   PrintFormat("--> [PROP AUDIT] %s", AuditTradeHistory());
   SaveState();
   if(h_atr     != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_tr_fast != INVALID_HANDLE) IndicatorRelease(h_tr_fast);
   if(h_tr_slow != INVALID_HANDLE) IndicatorRelease(h_tr_slow);
   if(h_tr_atr  != INVALID_HANDLE) IndicatorRelease(h_tr_atr);
   if(InpShowHUD) Comment("");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0. The account changed without a restart (or was unknown at start-up): park the old account's state under its
   //    own login, then load the new account's
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(login > 0 && login != g_login)
   {
      if(g_login > 0) SaveState();
      PrintFormat("--> [STATE] Account changed: %I64d -> %I64d", g_login, login);
      g_login = login;
      LoadState();
   }

   // 1. Guards: day rollover, prop floors, personal day stop
   UpdateGuards();

   // 1b. Prop: open runners must not be able to give back more than today's room
   GuardOpenGiveback();

   // 2. Invariant: every position carries a server-side SL and TP
   EnforceSafetyNet();

   // 2b. Weekend rule: flat before the close if the firm requires it
   if(IsWeekendFlatWindow() && HasExposure())
      FlattenAll(StringFormat("WEEKEND FLAT (Friday %02d:00 New York, 1h before the close)", WEEKEND_FLAT_NY));

   // 3. Closed bar: trail runners, exit on opposite breakout, look for a new breakout
   datetime bar_time = iTime(_Symbol, EXEC_TF, 0);
   if(bar_time > 0 && bar_time != g_last_bar)
   {
      if(OnNewBar(bar_time))
         g_last_bar = bar_time;   // otherwise data not ready yet: retry next tick
   }

   // 4. Execute the pending breakout signal while its entry bar is open
   if(g_signal_dir != 0)
   {
      if(g_signal_bar == bar_time)
         TryEnter();
      else
      {
         CountSkip("spread wide whole bar");
         g_signal_dir = 0;
      }
   }

   // 5. HUD (throttled)
   if(InpShowHUD && GetTickCount() - g_last_hud_ms > 500)
   {
      g_last_hud_ms = GetTickCount();
      UpdateHUD();
   }
}

//+------------------------------------------------------------------+
//| State Persistence (terminal global variables)                    |
//+------------------------------------------------------------------+
// Keyed by account too: a terminal that ran the EA on another account (a demo, an old challenge)
// must never hand that account's starting balance or equity peak to a new prop account.
// Uses the login remembered at start-up: during an account switch MT5 already reports the NEW login
// while the EA shuts down, and saving under it would hand the old account's state to the new one.
string GvName(const string key)
{
   long login = (g_login > 0) ? g_login : AccountInfoInteger(ACCOUNT_LOGIN);
   return "AEG3_" + IntegerToString(login) + "_" + _Symbol + "_" +
          IntegerToString(InpMagicNumber) + "_" + key;
}

//+------------------------------------------------------------------+
//| Account history: the firm measures from the account's real start |
//| and from the real start of each day, not from when the EA was     |
//| attached. Both are rebuilt from the deal history.                 |
//+------------------------------------------------------------------+
// First deposit (a prop account's size, and when it was made) and the highest balance the account has closed at
void ScanAccountHistory(double &first_deposit, double &peak_balance, datetime &first_time)
{
   first_deposit = 0.0;
   peak_balance  = 0.0;
   first_time    = 0;
   if(!HistorySelect(0, TimeCurrent() + 60)) return;
   double running = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      double amount = HistoryDealGetDouble(deal, DEAL_PROFIT);
      if(first_deposit <= 0.0 && (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BALANCE && amount > 0.0)
      {
         first_deposit = amount;
         first_time    = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      }
      running += amount + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_SWAP);
      peak_balance = MathMax(peak_balance, running);
   }
}

// Account balance at server time t, rebuilt from the deals booked since then
double BalanceAt(const datetime t)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(!HistorySelect(t, TimeCurrent() + 60)) return bal;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (datetime)HistoryDealGetInteger(deal, DEAL_TIME) < t) continue;
      bal -= HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_COMMISSION) +
             HistoryDealGetDouble(deal, DEAL_SWAP);
   }
   return bal;
}

double GvGet(const string key, const double fallback)
{
   if(!GlobalVariableCheck(GvName(key))) return fallback;
   return GlobalVariableGet(GvName(key));
}

void SaveState()
{
   GlobalVariableSet(GvName("init"),     g_init_balance);
   GlobalVariableSet(GvName("peak"),     g_peak_equity);
   GlobalVariableSet(GvName("peak_bal"), g_peak_balance);
   GlobalVariableSet(GvName("day_t"),    (double)g_day_start);
   GlobalVariableSet(GvName("day_base"), g_day_base);
   GlobalVariableSet(GvName("halt"),     (double)g_halt_until);
   for(int a = 0; a < ANCHOR_COUNT; a++)
   {
      GlobalVariableSet(GvName("ad" + IntegerToString(a)), (double)g_anchor_day[a]);
      GlobalVariableSet(GvName("ab" + IntegerToString(a)), g_anchor_base[a]);
      GlobalVariableSet(GvName("as" + IntegerToString(a)), (double)g_anchor_since[a]);
   }
}

void LoadState()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   // Strategy Tester always starts clean; live restarts restore the guard state
   bool fresh = (MQLInfoInteger(MQL_TESTER) != 0) || !GlobalVariableCheck(GvName("init"));
   double first_deposit = 0.0, hist_peak = 0.0;
   ScanAccountHistory(first_deposit, hist_peak, g_start_time);
   if(g_start_time <= 0) g_start_time = TimeCurrent();
   if(fresh)
   {
      g_init_balance = (InpInitialBalance > 0.0) ? InpInitialBalance : (first_deposit > 0.0 ? first_deposit : bal);
      g_peak_equity  = MathMax(MathMax(g_init_balance, eq), hist_peak);
      g_peak_balance = bal;
      g_day_start    = 0;
      g_halt_until   = 0;
   }
   else
   {
      g_init_balance = (InpInitialBalance > 0.0) ? InpInitialBalance : GvGet("init", bal);
      g_peak_equity  = MathMax(GvGet("peak", eq), g_init_balance);
      g_peak_balance = MathMax(GvGet("peak_bal", bal), bal);
      g_day_start    = (datetime)(long)GvGet("day_t", 0.0);
      g_day_base     = GvGet("day_base", MathMax(bal, eq));
      g_halt_until   = (datetime)(long)GvGet("halt", 0.0);
      if(g_halt_until > TimeCurrent()) g_halt_reason = "restored from previous session";
      for(int a = 0; a < ANCHOR_COUNT; a++)
      {
         g_anchor_day[a]   = (long)GvGet("ad" + IntegerToString(a), -1.0);
         g_anchor_base[a]  = GvGet("ab" + IntegerToString(a), 0.0);
         g_anchor_since[a] = (datetime)(long)GvGet("as" + IntegerToString(a), 0.0);
      }
   }
   PrintFormat("--> [STATE] %s | Initial balance: %.2f | Peak equity: %.2f",
               fresh ? "Fresh start" : "Restored", g_init_balance, g_peak_equity);
}

//+------------------------------------------------------------------+
//| Guards: day rollover, prop floors, personal day stop             |
//+------------------------------------------------------------------+
// Server-midnight trading day
datetime DayStart(const datetime t)
{
   long s = (long)t;
   return (datetime)(s - (s % 86400));
}

// Seconds on the wall clock of one prop reset convention (its midnight is the reset)
long AnchorLocal(const int anchor, const datetime t)
{
   long s = (long)t;
   if(g_clock_known)
   {
      if(anchor == ANCHOR_NY17)
         s = (long)ServerToNy(t) + 7 * 3600;            // 17:00 New York -> midnight
      else if(anchor == ANCHOR_UTC)
         s = (long)ServerToUtc(t);
      else if(anchor == ANCHOR_CET)
      {
         datetime utc = ServerToUtc(t);
         s = (long)utc + (EuDst(utc) ? 2 : 1) * 3600;
      }
   }
   return s;
}

// Day number of server time t under one prop reset convention
long AnchorDay(const int anchor, const datetime t)
{
   return AnchorLocal(anchor, t) / 86400;
}

// Server time at which that convention's current day began
datetime AnchorDayStart(const int anchor, const datetime t)
{
   return (datetime)((long)t - AnchorLocal(anchor, t) % 86400);
}

// The day base the daily limit is measured from: selected reset convention (or strictest of all four)
double PropDayBase()
{
   if(InpPropDayAnchor >= 0 && InpPropDayAnchor < ANCHOR_COUNT)
      return (g_anchor_base[InpPropDayAnchor] > 0.0) ? g_anchor_base[InpPropDayAnchor] : g_day_base;

   double base = g_day_base;
   for(int a = 0; a < ANCHOR_COUNT; a++)
      base = MathMax(base, g_anchor_base[a]);
   return base;
}

// Once the selected reset convention (or all four) has rolled over, a new day has started
datetime NextFullReset()
{
   if(InpPropDayAnchor >= 0 && InpPropDayAnchor < ANCHOR_COUNT && g_anchor_since[InpPropDayAnchor] > 0)
      return (datetime)((long)g_anchor_since[InpPropDayAnchor] + 86400);

   datetime until = (datetime)((long)g_day_start + 86400);
   for(int a = 0; a < ANCHOR_COUNT; a++)
      if(g_anchor_since[a] > 0)
         until = (datetime)MathMax((double)until, (double)((long)g_anchor_since[a] + 86400));
   return until;
}

// Friday close window: positions must be flat over the weekend (1h before gold's 17:00 NY close)
bool IsWeekendFlatWindow()
{
   if(!InpWeekendFlat) return false;
   MqlDateTime dt;
   if(g_clock_known)
   {
      TimeToStruct(ServerToNy(TimeCurrent()), dt);
      return (dt.day_of_week == 5 && dt.hour >= WEEKEND_FLAT_NY);
   }
   TimeToStruct(TimeCurrent(), dt);                     // clock not read yet: Friday 20:00 server
   return (dt.day_of_week == 5 && dt.hour >= 20);
}

bool IsHalted()
{
   return (TimeCurrent() < g_halt_until);
}

void Halt(const datetime until, const string reason)
{
   if(until <= g_halt_until) return;
   g_halt_until  = until;
   g_halt_reason = reason;
   g_last_event  = "HALT: " + reason;
   PrintFormat("--> [HALT] %s | No new entries until %s", reason, TimeToString(until, TIME_DATE | TIME_MINUTES));
   SaveState();
}

void UpdateGuards()
{
   datetime now = TimeCurrent();
   if(now <= 0) return;

   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   // A new day under each reset convention: its base is the balance at the day's real start
   // (rebuilt from history, so attaching mid-day after a loss cannot lower it) or equity, if higher
   bool changed = false;
   datetime day_start = DayStart(now);
   if(day_start != g_day_start)
   {
      g_day_start = day_start;
      g_day_base  = MathMax(eq, BalanceAt(day_start));
      changed = true;
   }
   for(int a = 0; a < ANCHOR_COUNT; a++)
   {
      long key = AnchorDay(a, now);
      if(key != g_anchor_day[a])
      {
         datetime since    = AnchorDayStart(a, now);
         g_anchor_day[a]   = key;
         g_anchor_base[a]  = MathMax(eq, BalanceAt(since));
         g_anchor_since[a] = since;
         changed = true;
      }
   }
   if(changed) SaveState();

   if(eq > g_peak_equity)
      g_peak_equity = eq;
   if(bal > g_peak_balance)
      g_peak_balance = bal;

   AuditPropLimits(eq, now);

   datetime tomorrow = (datetime)((long)day_start + 86400);
   double floor_level = EntryFloor();

   if(InpIsPropFirm)
   {
      // Prop: touching the buffered floor means flatten everything now, and wait until
      // every reset convention has started a new day
      if(eq <= floor_level)
      {
         if(HasExposure())
            FlattenAll(StringFormat("PROP FLOOR (equity %.2f <= %.2f)", eq, floor_level));
         Halt(NextFullReset(), "PROP FLOOR reached (daily / trailing guard)");
      }
      CheckChallengeTarget(eq, bal);
   }
   else if(eq <= floor_level)
   {
      // Personal: bad day -> stop adding exposure; open runners keep their stops
      Halt(tomorrow, StringFormat("DAY STOP (-%.1f%% today)", PERSONAL_DAY_STOP));
   }
}

//+------------------------------------------------------------------+
//| Floors                                                           |
//+------------------------------------------------------------------+
// Measured from the strictest day base, so the floor holds whichever reset time the firm uses.
// Firms take the 3% either of the day's base or of the initial balance: allow the smaller loss.
double PropDailyFloor()
{
   double base = PropDayBase();
   double ref  = (g_init_balance > 0.0) ? MathMin(base, g_init_balance) : base;
   return base - ref * (PROP_DAILY_PCT - PROP_BUFFER_PCT) / 100.0;
}

double PropTrailingFloor()
{
   double f = g_peak_equity - g_init_balance * (PROP_TRAIL_PCT - PROP_BUFFER_PCT) / 100.0;
   // Firms whose trailing drawdown freezes once it reaches your starting balance ("trailing to breakeven").
   // Without this the floor keeps rising with every floating-equity spike, and giving that spike back
   // permanently shrinks the room the EA is allowed to trade with.
   if(InpTrailLocksAtStart)
      f = MathMin(f, g_init_balance + g_init_balance * PROP_BUFFER_PCT / 100.0);
   return f;
}

//+------------------------------------------------------------------+
//| Prop audit: how close did equity get to the firm's REAL limits   |
//| (3% daily from each convention's day base, 6% trailing; no       |
//| buffer)? Tracked every tick in both modes, printed as one line   |
//| when the EA stops. A value at or past -3.00% / 0.00% is a breach.|
//+------------------------------------------------------------------+
void AuditPropLimits(const double eq, const datetime now)
{
   for(int a = 0; a < ANCHOR_COUNT; a++)
   {
      if(g_anchor_base[a] <= 0.0) continue;
      // Loss as a % of the smaller of day base and initial balance: the stricter of the two firm rules
      double ref = (g_init_balance > 0.0) ? MathMin(g_anchor_base[a], g_init_balance) : g_anchor_base[a];
      double pct = (eq - g_anchor_base[a]) / ref * 100.0;
      if(pct < g_audit_day[a]) { g_audit_day[a] = pct; g_audit_day_t[a] = now; }
   }
   if(g_init_balance <= 0.0) return;
   double real_trail = g_peak_equity - g_init_balance * PROP_TRAIL_PCT / 100.0;
   if(InpTrailLocksAtStart) real_trail = MathMin(real_trail, g_init_balance);
   double room = (eq - real_trail) / g_init_balance * 100.0;
   if(room < g_audit_trail) { g_audit_trail = room; g_audit_trail_t = now; }
}

// Rules only the closed trades can show: trades closed within 2 minutes, and the worst loss of one
// trade idea (Upcomers' 3% rule: same-direction positions on one symbol open together count as one trade)
string AuditTradeHistory()
{
   if(!HistorySelect(0, TimeCurrent() + 60)) return "trade history unavailable";
   int n = HistoryDealsTotal();

   // Our positions, in the order they were opened
   long     ids[];
   datetime t_open[], t_close[];
   int      dir[];
   double   pnl[];
   int      m = 0;
   for(int i = 0; i < n; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      ArrayResize(ids, m + 1);
      ArrayResize(t_open, m + 1);
      ArrayResize(t_close, m + 1);
      ArrayResize(dir, m + 1);
      ArrayResize(pnl, m + 1);
      ids[m]     = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      t_open[m]  = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      t_close[m] = 0;
      dir[m]     = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
      pnl[m]     = 0.0;
      m++;
   }
   // Every deal of those positions (a stop-loss exit may not carry our magic number)
   for(int i = 0; i < n; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      long pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      for(int k = m - 1; k >= 0; k--)
      {
         if(ids[k] != pid) continue;
         pnl[k] += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(deal, DEAL_SWAP);
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
            t_close[k] = (datetime)MathMax((double)t_close[k], (double)HistoryDealGetInteger(deal, DEAL_TIME));
         break;
      }
   }

   int  quick = 0;
   long shortest = -1;
   double worst_idea = 0.0, idea = 0.0;
   int    idea_dir = 0;
   datetime idea_end = 0;
   for(int k = 0; k < m; k++)
   {
      if(t_close[k] > 0)
      {
         long held = (long)t_close[k] - (long)t_open[k];
         if(held < MIN_HOLD_SEC) quick++;
         if(shortest < 0 || held < shortest) shortest = held;
      }
      if(dir[k] == idea_dir && t_open[k] < idea_end)
         idea += pnl[k];                                    // joins the open idea
      else
      {
         idea = pnl[k];
         idea_dir = dir[k];
         idea_end = 0;
      }
      idea_end   = (datetime)MathMax((double)idea_end, (double)(t_close[k] > 0 ? t_close[k] : TimeCurrent()));
      worst_idea = MathMin(worst_idea, idea);
   }
   double worst_pct = (g_init_balance > 0.0) ? -worst_idea / g_init_balance * 100.0 : 0.0;
   return StringFormat("Positions %d, closed within 2 minutes: %d (shortest %I64ds) | Worst trade-idea loss: %.2f%% of the initial balance (3%% rule: %s)",
                       m, quick, MathMax(shortest, 0), worst_pct, (worst_pct >= 3.0) ? "BREACH" : "ok");
}

string AuditLine()
{
   string names[ANCHOR_COUNT] = {"server midnight", "17:00 NY", "00:00 UTC", "00:00 CET"};
   string s = "";
   bool breach = (g_audit_trail <= 0.0);
   for(int a = 0; a < ANCHOR_COUNT; a++)
   {
      s += StringFormat("%s %.2f%% (%s)%s", names[a], g_audit_day[a], TimeToString(g_audit_day_t[a], TIME_DATE),
                        (a < ANCHOR_COUNT - 1) ? ", " : "");
      if(g_audit_day[a] <= -PROP_DAILY_PCT) breach = true;
   }
   return StringFormat("Worst day vs the %.0f%% daily limit, per reset time: %s | Closest to the %.0f%% trailing floor: %.2f%% of start above it (%s) | %s",
                       PROP_DAILY_PCT, s, PROP_TRAIL_PCT, g_audit_trail, TimeToString(g_audit_trail_t, TIME_DATE),
                       breach ? "BREACH" : "no breach");
}

//+------------------------------------------------------------------+
//| Challenge target: firms count the target on CLOSED balance with  |
//| every position closed, and trading on after it only risks giving |
//| it back. Once equity clears the target (plus closing costs) bank |
//| everything; once the balance is over it and the account is flat, |
//| stop for good. If closing slipped below the target, keep going.  |
//+------------------------------------------------------------------+
void CheckChallengeTarget(const double eq, const double bal)
{
   if(InpPropTargetPct <= 0.0 || g_init_balance <= 0.0 || g_target_done) return;
   double target = g_init_balance * (1.0 + InpPropTargetPct / 100.0);

   if(HasExposure())
   {
      if(eq >= target + g_init_balance * TARGET_CUSHION_PCT / 100.0)
         FlattenAll(StringFormat("CHALLENGE TARGET +%.1f%% in reach (equity %.2f >= %.2f): banking it", InpPropTargetPct, eq, target));
      return;
   }
   if(bal < target) return;

   g_target_done = true;
   PrintFormat("--> [TARGET] Challenge target +%.1f%% reached: balance %.2f >= %.2f, all positions closed, %d days after the start. Trading stopped.",
               InpPropTargetPct, bal, target, (int)(((long)TimeCurrent() - (long)g_start_time) / 86400));
   Halt(D'2099.12.31', StringFormat("challenge target +%.1f%% reached - wait for the firm to upgrade the account", InpPropTargetPct));
}

// The equity level no new trade may put at risk
double EntryFloor()
{
   if(InpIsPropFirm)
      return MathMax(PropDailyFloor(), PropTrailingFloor());
   return g_day_base * (1.0 - PERSONAL_DAY_STOP / 100.0);
}

//+------------------------------------------------------------------+
//| Money lost if price travels from 'from_price' to 'to_price'      |
//| (positive; 0 when favourable). OrderCalcProfit first: broker     |
//| tick values are unreliable on some gold symbols.                 |
//+------------------------------------------------------------------+
double LossMoney(const string symbol, const bool is_buy, const double volume, const double from_price, const double to_price)
{
   if(volume <= 0.0) return 0.0;
   double pnl = 0.0;
   if(!OrderCalcProfit(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, volume, from_price, to_price, pnl))
   {
      // Fallback only. Some gold symbols disagree with themselves (Upcomers XAUUSD: TickValue 0.10
      // with Contract 100, a 10x gap), so take the LARGER of the two losses: a missing quote must
      // never make a position look smaller than it is, in sizing or in the risk budget.
      double diff = is_buy ? (from_price - to_price) : (to_price - from_price);   // > 0 = a loss
      if(diff <= 0.0) return 0.0;
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double contract   = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double by_tick    = (tick_value > 0.0 && tick_size > 0.0) ? diff / tick_size * tick_value * volume : 0.0;
      double by_size    = (contract > 0.0) ? diff * contract * volume : 0.0;
      return MathMax(by_tick, by_size);
   }
   return (pnl < 0.0) ? -pnl : 0.0;
}

// Worst-case additional loss of EVERY open position on the account (current price -> SL).
// Account-wide on purpose: running this EA on two symbols must not double the real risk.
double OpenRiskMoney()
{
   double risk = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0) continue;
      string sym    = PositionGetString(POSITION_SYMBOL);
      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double sl     = PositionGetDouble(POSITION_SL);
      double px     = is_buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      if(px <= 0.0) continue;
      double stop   = sl;
      if(stop <= 0.0)
      {
         // No stop on that position (not ours, or broker rejected): assume our own worst case
         double fallback = SL_ATR * Atr();
         if(sym != _Symbol) fallback = px * 0.02;
         stop = is_buy ? px - fallback : px + fallback;
      }
      risk += LossMoney(sym, is_buy, PositionGetDouble(POSITION_VOLUME), px, stop);
   }
   return risk;
}

//+------------------------------------------------------------------+
//| Prop: keep open trades' giveback inside the room left today.     |
//| The daily limit is measured from start-of-day EQUITY, which      |
//| includes floating profit. A runner that gives that profit back   |
//| counts as a daily loss even while it is still in the money, so   |
//| a big overnight winner could breach the limit on a normal        |
//| pullback. When the combined distance-to-stop of every open       |
//| position exceeds 90% of the room above the floor, our stops are  |
//| tightened proportionally so the worst case fits.                 |
//| In simulation: 7 of 47 180-day challenges breached without this, |
//| 0 of 47 with it, at no cost to 2026 returns.                     |
//+------------------------------------------------------------------+
void GuardOpenGiveback()
{
   if(!InpIsPropFirm) return;

   double room = AccountInfoDouble(ACCOUNT_EQUITY) - EntryFloor();
   if(room <= 0.0) return;                          // at the floor: UpdateGuards flattens instead

   double exposure = OpenRiskMoney();               // account-wide, current price -> stop
   double allowed  = room * OPEN_RISK_FRACTION;
   if(exposure <= 0.0 || exposure <= allowed) return;

   double scale   = allowed / exposure;
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double min_gap = MinStopDistance();
   double step    = 0.05 * Atr();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0) continue;                       // the safety net will add one

      double px       = is_buy ? bid : ask;
      double loss     = LossMoney(_Symbol, is_buy, vol, px, sl);
      double per_unit = LossMoney(_Symbol, is_buy, vol, px, is_buy ? px - 1.0 : px + 1.0);
      if(loss <= 0.0 || per_unit <= 0.0) continue;

      double dist   = loss * scale / per_unit;
      double new_sl = NormPrice(is_buy ? px - dist : px + dist);
      bool tighter  = is_buy ? (new_sl > sl + step) : (new_sl < sl - step);
      if(!tighter) continue;

      bool legal = is_buy ? (px - new_sl >= min_gap) : (new_sl - px >= min_gap);
      if(legal)
      {
         if(g_trade.PositionModify(ticket, new_sl, tp))
            PrintFormat("--> [DAILY GUARD] #%I64u SL %s -> %s (open giveback %.2f > %.0f%% of today's room %.2f)",
                        ticket, Px(sl), Px(new_sl), exposure, OPEN_RISK_FRACTION * 100.0, room);
      }
      else if(((long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME) >= MIN_HOLD_SEC) && g_trade.PositionClose(ticket))
         PrintFormat("--> [DAILY GUARD] #%I64u closed: no legal stop fits inside today's room %.2f", ticket, room);
   }
}

double RoomMoney()
{
   return AccountInfoDouble(ACCOUNT_EQUITY) - EntryFloor() - OpenRiskMoney();
}

// Risk for the next unit: % of equity (compounds with the account), bounded by the 3.2x Prop Room Governor
double RiskMoneyForNextTrade()
{
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double money = eq * ProfileRiskPercent() / 100.0;
   double room  = RoomMoney();
   if(InpIsPropFirm)
   {
      if(g_init_balance > 0.0)
         money = MathMin(money, g_init_balance * PROP_MAX_IDEA_PCT / 100.0);
      return MathMin(money, room / 3.2);
   }
   return MathMin(money, room);
}

// Risk % for the next unit according to the selected profile
double ProfileRiskPercent()
{
   if(InpIsPropFirm) return InpPropRiskPercent;

   switch(InpRiskProfile)
   {
      case PROFILE_AGGRESSIVE:
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double dd  = (g_peak_balance > 0.0) ? (g_peak_balance - bal) / g_peak_balance * 100.0 : 0.0;
         return MathMax(AGGR_MIN_RISK, AGGR_MAX_RISK * (1.0 - dd / AGGR_DD_SPAN));
      }
      case PROFILE_MAXIMUM: return MAX_PROFILE_RISK;
      case PROFILE_CUSTOM:  return InpRiskPercent;
   }
   return 1.0;   // PROFILE_STEADY
}

//+------------------------------------------------------------------+
//| Position sizing                                                  |
//+------------------------------------------------------------------+
double NormalizeVolume(const double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(MathFloor(lots / step + 1e-9) * step, digits);
}

double LotsForRisk(const bool is_buy, const double entry, const double sl, const double risk_money)
{
   if(risk_money <= 0.0) return 0.0;
   double loss_per_lot = LossMoney(_Symbol, is_buy, 1.0, entry, sl);
   if(loss_per_lot <= 0.0) return 0.0;

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(min_lot <= 0.0) min_lot = 0.01;
   if(max_lot <= 0.0) max_lot = 100.0;

   double lots = NormalizeVolume(risk_money / loss_per_lot);
   if(lots < min_lot)
   {
      // Anti-Zeno min-lot recovery: allow 0.01 lot recovery trades when they safely fit within 80% of remaining room
      double eq           = AccountInfoDouble(ACCOUNT_EQUITY);
      double min_lot_risk = min_lot * loss_per_lot;
      double room_left    = RoomMoney();
      double allowed      = InpIsPropFirm ? MathMax(risk_money * 1.15, MathMin(room_left * 0.80, eq * 0.0065))
                                          : MathMax(risk_money * 1.1, eq * InpMaxMinLotRiskPct / 100.0);
      if(min_lot_risk > allowed || min_lot_risk > room_left)
      {
         g_last_event = StringFormat("SKIP: min lot risks %.2f (%.1f%% of equity) > allowed %.2f",
                                     min_lot_risk, min_lot_risk / MathMax(eq, 1.0) * 100.0, allowed);
         return 0.0;
      }
      lots = min_lot;
   }
   lots = MathMin(lots, max_lot);

   // Margin sufficiency (prevents 10019 NO_MONEY)
   double margin = 0.0;
   if(OrderCalcMargin(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, entry, margin) && margin > 0.0)
   {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.8;
      if(margin > free_margin)
      {
         lots = NormalizeVolume(lots * free_margin / margin);
         if(lots < min_lot)
         {
            g_last_event = "SKIP: not enough free margin";
            return 0.0;
         }
      }
   }
   return lots;
}

//+------------------------------------------------------------------+
//| New York data-hour range (13:00-14:00 UTC by default).           |
//| Breakouts of that hour, in the H4 trend direction, were positive |
//| in 2022-24 and 2025-26 independently.                            |
//+------------------------------------------------------------------+
bool GetNyRange(const int range_hour, double &range_hi, double &range_lo)
{
   range_hi = 0.0;
   range_lo = 0.0;
   datetime now = TimeCurrent();
   MqlDateTime dt_now;
   TimeToStruct(now, dt_now);

   bool found = false;
   for(int i = 1; i < 96; i++)
   {
      datetime bt = iTime(_Symbol, EXEC_TF, i);
      if(bt <= 0) break;
      MqlDateTime dt;
      TimeToStruct(bt, dt);
      if(dt.day != dt_now.day || dt.mon != dt_now.mon) break;      // previous day: stop
      if(dt.hour > range_hour) continue;                           // after the range hour
      if(dt.hour < range_hour) break;                              // before it: done

      double bh = iHigh(_Symbol, EXEC_TF, i);
      double bl = iLow(_Symbol, EXEC_TF, i);
      if(bh <= 0.0 || bl <= 0.0) continue;
      range_hi = found ? MathMax(range_hi, bh) : bh;
      range_lo = found ? MathMin(range_lo, bl) : bl;
      found = true;
   }
   return found;
}

// Returns +1 / -1 on a fresh close beyond the range in the trend direction, else 0.
// sl_dist is set to the range width, clamped to the usual ATR bounds.
int NySignal(const double c1, const double c2, double &sl_dist)
{
   sl_dist = 0.0;
   if(!InpUseNySession || !g_clock_known || g_trend == 0) return 0;

   int range_hour = SessionHourServer();
   if(range_hour + InpNyWindowHours > 23) return 0;             // window would cross server midnight (UTC+7 and beyond)

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour <= range_hour || dt.hour > range_hour + InpNyWindowHours) return 0;

   double rh = 0.0, rl = 0.0;
   if(!GetNyRange(range_hour, rh, rl) || rh <= rl) return 0;

   double width = rh - rl;
   if(width < 0.2 * g_atr_value || width > 3.0 * g_atr_value) return 0;

   int dir = 0;
   if(g_trend == 1 && c1 > rh && c2 <= rh)       dir = 1;
   else if(g_trend == -1 && c1 < rl && c2 >= rl) dir = -1;
   if(dir == 0) return 0;

   sl_dist = MathMax(MathMin(width, SL_ATR * g_atr_value), InpMinStopAtr * g_atr_value);
   return dir;
}

int LonSignal(const double c1, const double c2, double &sl_dist)
{
   sl_dist = 0.0;
   if(!InpUseLondonSession || !g_clock_known || g_trend == 0) return 0;

   int range_hour = LondonHourServer();
   if(range_hour + InpLonWindowHours > 23) return 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour <= range_hour || dt.hour > range_hour + InpLonWindowHours) return 0;

   double rh = 0.0, rl = 0.0;
   if(!GetNyRange(range_hour, rh, rl) || rh <= rl) return 0;

   double width = rh - rl;
   if(width < 0.2 * g_atr_value || width > 2.8 * g_atr_value) return 0;

   int dir = 0;
   if(g_trend == 1 && c1 > rh && c2 <= rh)       dir = 1;
   else if(g_trend == -1 && c1 < rl && c2 >= rl) dir = -1;
   if(dir == 0) return 0;

   sl_dist = MathMax(MathMin(width, SL_ATR * g_atr_value), InpMinStopAtr * g_atr_value);
   return dir;
}

//+------------------------------------------------------------------+
//| Closed bar: trail, opposite-breakout exit, new signal            |
//| Returns false only when indicator data is not ready (retry).     |
//+------------------------------------------------------------------+
bool OnNewBar(const datetime bar_time)
{
   double atr_buf[1];
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf) < 1) return false;

   // A market break just ended (daily 17:00-18:00 NY halt or the weekend): re-read the broker clock
   datetime prev_bar = iTime(_Symbol, EXEC_TF, 1);
   if(!g_clock_known || (prev_bar > 0 && (long)bar_time - (long)prev_bar >= BREAK_MIN_GAP))
      RefreshBrokerClock();

   double c1       = iClose(_Symbol, EXEC_TF, 1);
   double c2       = iClose(_Symbol, EXEC_TF, 2);
   int    ih1      = iHighest(_Symbol, EXEC_TF, MODE_HIGH, g_channel_bars, 2);
   int    ih2      = iHighest(_Symbol, EXEC_TF, MODE_HIGH, g_channel_bars, 3);
   int    il1      = iLowest(_Symbol, EXEC_TF, MODE_LOW, g_channel_bars, 2);
   int    il2      = iLowest(_Symbol, EXEC_TF, MODE_LOW, g_channel_bars, 3);
   if(atr_buf[0] <= 0.0 || c1 <= 0.0 || c2 <= 0.0 || ih1 < 0 || ih2 < 0 || il1 < 0 || il2 < 0)
      return false;

   double hh1 = iHigh(_Symbol, EXEC_TF, ih1);
   double hh2 = iHigh(_Symbol, EXEC_TF, ih2);
   double ll1 = iLow(_Symbol, EXEC_TF, il1);
   double ll2 = iLow(_Symbol, EXEC_TF, il2);

   g_atr_value  = atr_buf[0];
   g_channel_hi = hh1;
   g_channel_lo = ll1;

   // Trend filter on H4: close > EMA20 > EMA50 (mirror for down), and not stretched far from EMA50.
   // H4 needs ~9 days of history, so the Strategy Tester is usable from the second week of any test.
   g_trend = 0;
   double fast_buf[1], slow_buf[1], tr_atr_buf[1];
   int    tr_bars  = Bars(_Symbol, TREND_TF);
   double tr_close = iClose(_Symbol, TREND_TF, 1);
   bool   tr_ready = (tr_bars >= MIN_TREND_BARS && tr_close > 0.0 &&
                      CopyBuffer(h_tr_fast, 0, 1, 1, fast_buf) == 1 &&
                      CopyBuffer(h_tr_slow, 0, 1, 1, slow_buf) == 1 &&
                      CopyBuffer(h_tr_atr, 0, 1, 1, tr_atr_buf) == 1 && tr_atr_buf[0] > 0.0);
   if(!tr_ready)
   {
      if(g_warmup_bars == 0)
         PrintFormat("--> [WARMUP] Only %d %s bars of history (need %d, about %d days). No entries until the trend filter is reliable.",
                     tr_bars, EnumToString(TREND_TF), MIN_TREND_BARS, MIN_TREND_BARS * PeriodSeconds(TREND_TF) / 86400);
      g_warmup_bars++;
      g_last_event = StringFormat("Warming up: %d / %d %s bars", tr_bars, MIN_TREND_BARS, EnumToString(TREND_TF));
   }
   else
   {
      g_stretch = MathAbs(tr_close - slow_buf[0]) / tr_atr_buf[0];
      double ema_gap_atr = (slow_buf[0] - fast_buf[0]) / tr_atr_buf[0];
      if(g_stretch < TREND_MAX_STRETCH)
      {
         if(tr_close > fast_buf[0] && fast_buf[0] > slow_buf[0])
            g_trend = 1;
         else if(tr_close < fast_buf[0] && fast_buf[0] < slow_buf[0] && ema_gap_atr >= 0.55 && g_stretch >= 1.15 && g_stretch < 4.50)
            g_trend = -1;
      }
   }

   // Fresh close through the channel, in the H4 trend's direction
   int signal = 0;
   g_signal_sl = SL_ATR * g_atr_value;
   g_signal_is_ny  = false;
   g_signal_is_lon = false;
   if(g_trend == 1 && c1 > hh1 && c2 <= hh2)       signal = 1;
   else if(g_trend == -1 && c1 < ll1 && c2 >= ll2) signal = -1;

   // Otherwise: New York data-hour (13:00 UTC) or London Open (07:00 UTC) range breakout (stop = range width)
   if(signal == 0)
   {
      double ny_sl = 0.0;
      int ny = NySignal(c1, c2, ny_sl);
      if(ny != 0)
      {
         signal = ny;
         g_signal_sl = ny_sl;
         g_signal_is_ny = true;
      }
      else
      {
         double lon_sl = 0.0;
         int lon = LonSignal(c1, c2, lon_sl);
         if(lon != 0)
         {
            signal = lon;
            g_signal_sl = lon_sl;
            g_signal_is_lon = true;
         }
      }
   }

   SampleSpread();

   // Manage runners on the closed bar (exactly as researched)
   ManageOnBarClose(c1, signal);
   UpdateMonthPnl();

   if(signal != 0)
   {
      g_signal_dir    = signal;
      g_signal_bar    = bar_time;
      g_signal_logged = false;
      if(signal > 0) g_sig_long++; else g_sig_short++;
      PrintFormat("--> [SIGNAL] %s breakout: close %s beyond %dh %s %s | H4 trend %s | ATR %s",
                  signal > 0 ? "BULL" : "BEAR", Px(c1), CHANNEL_HOURS, signal > 0 ? "high" : "low",
                  Px(signal > 0 ? hh1 : ll1), signal > 0 ? "UP" : "DOWN", Px(g_atr_value));
   }
   return true;
}

//+------------------------------------------------------------------+
//| Entry gate + execution for the current signal                    |
//+------------------------------------------------------------------+
bool EntryBlocked(const int dir, string &why, string &key, bool &permanent)
{
   permanent = false;
   key = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      why = "AutoTrading OFF (toolbar 'Algo Trading' / F7 Common tab)";
      key = "autotrading off";
      return true;
   }
   if(IsHalted())
   {
      why = "halted: " + g_halt_reason;
      key = "halted";
      permanent = true;
      return true;
   }

   // Units: same direction only; add only when every open unit is risk-free
   int units = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsOurPosition()) continue;
      units++;
      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      if((dir > 0) != is_buy)
      {
         why = "opposite position still open";
         key = "opposite open";
         permanent = true;
         return true;
      }
      bool free = is_buy ? (sl >= open) : (sl > 0.0 && sl <= open);
      if(!free)
      {
         why = "existing unit not risk-free yet";
         key = "unit not risk-free";
         permanent = true;
         return true;
      }
   }
   int max_units = MaxUnits();
   if(units >= max_units)
   {
      why = "max units open";
      key = "max units";
      permanent = true;
      return true;
   }

   if(IsWeekendFlatWindow())
   {
      why = "weekend flat window";
      key = "weekend flat";
      permanent = true;
      return true;
   }

   // Clock-free protection against the daily rollover: the spread itself tells us when to stay out.
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double normal = MedianSpread();
   if(normal > 0.0 && spread > SPREAD_SPIKE_MULT * normal)
   {
      why = StringFormat("spread %s > %.1fx its normal %s (rollover / news)", Px(spread), SPREAD_SPIKE_MULT, Px(normal));
      key = "spread spike";
      return true;
   }
   if(g_atr_value > 0.0 && spread > MAX_SPREAD_ATR * g_atr_value)
   {
      why = StringFormat("spread %s > %.0f%% of ATR", Px(spread), MAX_SPREAD_ATR * 100.0);
      key = "spread";
      return true;
   }
   return false;
}

void TryEnter()
{
   int  dir = g_signal_dir;
   string why = "";
   string key = "";
   bool permanent = false;
   if(EntryBlocked(dir, why, key, permanent))
   {
      g_last_event = StringFormat("%s signal skipped: %s", dir > 0 ? "BUY" : "SELL", why);
      if(!g_signal_logged)
      {
         PrintFormat("--> [NO ENTRY] %s", g_last_event);
         g_signal_logged = true;
      }
      if(permanent)
      {
         CountSkip(key);
         g_signal_dir = 0;
      }
      return;
   }

   bool   is_buy = (dir > 0);
   double entry  = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist   = (g_signal_sl > 0.0) ? g_signal_sl : SL_ATR * g_atr_value;
   double sl     = NormPrice(is_buy ? entry - dist : entry + dist);
   double tp     = NormPrice(is_buy ? entry + TP_R * dist : entry - TP_R * dist);

   double risk_money = RiskMoneyForNextTrade();
   double lots = LotsForRisk(is_buy, entry, sl, risk_money);
   g_signal_dir = 0;   // one attempt per signal once the gate is open
   if(lots <= 0.0)
   {
      if(StringFind(g_last_event, "SKIP") != 0)
         g_last_event = "SKIP: no risk room left";
      PrintFormat("--> [NO ENTRY] %s", g_last_event);
      CountSkip(StringFind(g_last_event, "min lot") >= 0 ? "min lot too risky" : "risk room / margin");
      return;
   }

   if(!ExecuteMarket(is_buy, lots, sl, tp, StringFormat("AEG2 %s%s", g_signal_is_ny ? "NY " : "", is_buy ? "long" : "short")))
   {
      CountSkip("order rejected");
      return;
   }
   if(is_buy) g_entry_long++; else g_entry_short++;

   // The size was set for 'dist'; if the fill slipped (news spike, execution delay), move SL and TP
   // with it so the trade can never lose more than planned
   double fill = g_trade.ResultPrice();
   if(fill > 0.0 && MathAbs(fill - entry) >= 2.0 * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))
      ReanchorToFill(is_buy, fill, dist, entry, sl, tp);

   g_last_event = StringFormat("%s %.2f lots @ %s | SL %s | TP %s | risk %.2f (%.2f%%)",
                               is_buy ? "BUY" : "SELL", lots, Px(entry), Px(sl), Px(tp),
                               LossMoney(_Symbol, is_buy, lots, entry, sl),
                               LossMoney(_Symbol, is_buy, lots, entry, sl) / AccountInfoDouble(ACCOUNT_EQUITY) * 100.0);
   PrintFormat("==> [ENTRY] %s", g_last_event);
}

// Re-anchor a fresh position's SL/TP to its actual fill price, keeping the planned stop distance.
// entry / sl / tp are updated for the log. If price has already run through the re-anchored stop,
// the position is closed at once (a loss no bigger than planned).
void ReanchorToFill(const bool is_buy, const double fill, const double dist, double &entry, double &sl, double &tp)
{
   ulong deal = g_trade.ResultDeal();
   if(deal == 0 || !HistoryDealSelect(deal)) return;
   ulong ticket = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

   double new_sl = NormPrice(is_buy ? fill - dist : fill + dist);
   double new_tp = NormPrice(is_buy ? fill + TP_R * dist : fill - TP_R * dist);
   double px     = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap    = MinStopDistance();
   PrintFormat("--> [FILL] requested %s, filled %s (slippage %s): SL %s -> %s, TP %s -> %s",
               Px(entry), Px(fill), Px(is_buy ? fill - entry : entry - fill), Px(sl), Px(new_sl), Px(tp), Px(new_tp));

   if((is_buy && px - new_sl >= gap) || (!is_buy && new_sl - px >= gap))
   {
      if(!g_trade.PositionModify(ticket, new_sl, new_tp))
         PrintFormat("--> [FILL] #%I64u could not move SL/TP (retcode %u); keeping the original ones", ticket, g_trade.ResultRetcode());
   }
   else
      PrintFormat("--> [FILL] #%I64u keeping initial broker SL %s (respecting 120s min-hold rule)", ticket, Px(sl));
   entry = fill;
   sl    = new_sl;
   tp    = new_tp;
}

//+------------------------------------------------------------------+
//| Order submission with filling-mode fallback (retcode 10030)      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   ENUM_SYMBOL_TRADE_EXECUTION exec_mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   return (exec_mode == SYMBOL_TRADE_EXECUTION_MARKET) ? ORDER_FILLING_IOC : ORDER_FILLING_FOK;
}

bool ExecuteMarket(const bool is_buy, const double lots, const double sl, const double tp, const string cmt)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool ok = is_buy ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt)
                       : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
         return true;

      if(rc != TRADE_RETCODE_INVALID_FILL)
      {
         g_last_event = StringFormat("Order failed: retcode %u (%s)", rc, g_trade.ResultComment());
         PrintFormat("--> [ORDER FAILED] %s %.2f lots | SL %s TP %s | %s", is_buy ? "BUY" : "SELL", lots, Px(sl), Px(tp), g_last_event);
         return false;
      }
      g_filling = (g_filling == ORDER_FILLING_IOC) ? ORDER_FILLING_FOK :
                  (g_filling == ORDER_FILLING_FOK) ? ORDER_FILLING_RETURN : ORDER_FILLING_IOC;
      g_trade.SetTypeFilling(g_filling);
      PrintFormat("--> [FILLING RETRY] Switching to %s", EnumToString(g_filling));
   }
   return false;
}

//+------------------------------------------------------------------+
//| Runner management on each closed bar:                            |
//| - opposite breakout (daily trend flipped) -> exit                |
//| - chandelier: SL ratchets to close -/+ 5 ATR, never loosens      |
//+------------------------------------------------------------------+
void ManageOnBarClose(const double close1, const int signal)
{
   double a = g_atr_value;
   if(a <= 0.0) return;

   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread  = ask - bid;
   double min_gap = MinStopDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      // Discretionary exits wait until the position is 2 minutes old (sub-2-minute trades read as tick scalping)
      bool   young  = ((long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME) < MIN_HOLD_SEC);

      if((is_buy && signal < 0) || (!is_buy && signal > 0))
      {
         if(!young && g_trade.PositionClose(ticket))
            PrintFormat("--> [TREND EXIT] #%I64u closed: opposite breakout with the daily trend flipped", ticket);
         continue;
      }

      double ref    = is_buy ? close1 : close1 + spread;
      double target = is_buy ? ref - TRAIL_ATR * a : ref + TRAIL_ATR * a;

      // Once price closes >= 4.2 ATR in profit, lock breakeven (+0.05 ATR) while keeping > 4.15 ATR of runner room
      double profit_atr = is_buy ? (close1 - open) / a : (open - close1) / a;
      if(profit_atr >= 4.2)
      {
         double be_lock = is_buy ? (open + 0.05 * a) : (open - 0.05 * a);
         target = is_buy ? MathMax(target, be_lock) : MathMin(target, be_lock);
      }

      target = NormPrice(target);
      bool   better = is_buy ? (target > sl) : (sl <= 0.0 || target < sl);
      if(!better) continue;

      bool legal = is_buy ? (bid - target >= min_gap) : (target - ask >= min_gap);
      if(legal)
      {
         if(g_trade.PositionModify(ticket, target, tp))
            PrintFormat("--> [TRAIL] #%I64u SL %s -> %s (%s)", ticket, Px(sl), Px(target),
                        (is_buy ? target >= open : target <= open) ? "profit locked" : "risk reduced");
      }
      else if(!young && ((is_buy && bid <= target) || (!is_buy && ask >= target)))
      {
         // Price already through the new stop level: take the exit the stop would have given
         if(g_trade.PositionClose(ticket))
            PrintFormat("--> [TRAIL EXIT] #%I64u price already beyond trail level %s", ticket, Px(target));
      }
   }
}

//+------------------------------------------------------------------+
//| Safety net: every position must carry SL and TP                  |
//+------------------------------------------------------------------+
void EnforceSafetyNet()
{
   double a = Atr();
   if(a <= 0.0) return;

   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double min_gap = MinStopDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl > 0.0 && tp > 0.0) continue;

      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double dist   = SL_ATR * a;
      double px     = is_buy ? bid : ask;
      double new_sl = (sl > 0.0) ? sl : NormPrice(is_buy ? open - dist : open + dist);
      double new_tp = (tp > 0.0) ? tp : NormPrice(is_buy ? open + TP_R * dist : open - TP_R * dist);

      if((is_buy && px <= new_sl + min_gap) || (!is_buy && px >= new_sl - min_gap))
      {
         PrintFormat("--> [SAFETY NET] #%I64u has no SL and price is beyond the emergency stop. Closing.", ticket);
         g_trade.PositionClose(ticket);
         continue;
      }
      if((is_buy && new_tp <= px + min_gap) || (!is_buy && new_tp >= px - min_gap))
         new_tp = NormPrice(is_buy ? px + dist : px - dist);

      if(g_trade.PositionModify(ticket, new_sl, new_tp))
         PrintFormat("--> [SAFETY NET] #%I64u missing SL/TP restored: SL %s TP %s", ticket, Px(new_sl), Px(new_tp));
   }
}

void FlattenAll(const string reason)
{
   // The guards call this on every tick until flat. Log a repeat of the same reason at most once a minute,
   // or once every 10 minutes when closing cannot work because AutoTrading is OFF in this terminal (e.g. the
   // local copy of an EA that trades on a VPS); then no orders are sent either, they would only be rejected.
   bool can_trade = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) && (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   int  cut = StringFind(reason, " (");
   string key = (cut > 0) ? StringSubstr(reason, 0, cut) : reason;
   int  every = can_trade ? 60 : 600;
   if(key != g_flatten_key || (long)TimeCurrent() - (long)g_flatten_t >= every)
   {
      PrintFormat("--> [FLATTEN] %s%s", reason, can_trade ? "" : " | cannot close here: AutoTrading is OFF in this terminal");
      g_flatten_key = key;
      g_flatten_t   = TimeCurrent();
   }
   g_last_event = "FLATTEN: " + reason;
   if(!can_trade) return;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool all_closed = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsOurPosition()) continue;
         if(!g_trade.PositionClose(ticket)) all_closed = false;
      }
      if(all_closed) break;
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsOurPosition()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

int CountUnits()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsOurPosition()) count++;
   return count;
}

// Netting accounts can only hold one position per symbol
int MaxUnits()
{
   return g_is_netting ? 1 : InpMaxUnits;
}

bool HasExposure()
{
   return (CountUnits() > 0);
}

double NormPrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

string Px(const double price)
{
   return DoubleToString(price, _Digits);
}

// Minimum legal distance between current price and a stop level
double MinStopDistance()
{
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops, freeze) * _Point + 2.0 * _Point;
}

double Atr()
{
   if(g_atr_value > 0.0) return g_atr_value;
   double buf[1];
   if(CopyBuffer(h_atr, 0, 1, 1, buf) < 1) return 0.0;
   g_atr_value = buf[0];
   return g_atr_value;
}

// Rolling median of the spread: what "normal" looks like on this symbol and broker
void SampleSpread()
{
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spread <= 0.0) return;
   if(ArraySize(g_spread_hist) != SPREAD_SAMPLES)
   {
      ArrayResize(g_spread_hist, SPREAD_SAMPLES);
      ArrayInitialize(g_spread_hist, 0.0);
      g_spread_pos = 0;
      g_spread_count = 0;
   }
   g_spread_hist[g_spread_pos] = spread;
   g_spread_pos = (g_spread_pos + 1) % SPREAD_SAMPLES;
   if(g_spread_count < SPREAD_SAMPLES) g_spread_count++;
}

double MedianSpread()
{
   if(g_spread_count < 20) return 0.0;      // not enough samples yet
   double tmp[];
   ArrayResize(tmp, g_spread_count);
   for(int i = 0; i < g_spread_count; i++) tmp[i] = g_spread_hist[i];
   ArraySort(tmp);
   return tmp[g_spread_count / 2];
}

void CountSkip(const string key)
{
   int n = ArraySize(g_skip_keys);
   for(int i = 0; i < n; i++)
   {
      if(g_skip_keys[i] == key)
      {
         g_skip_counts[i]++;
         return;
      }
   }
   ArrayResize(g_skip_keys, n + 1);
   ArrayResize(g_skip_counts, n + 1);
   g_skip_keys[n]   = key;
   g_skip_counts[n] = 1;
}

// Closed P/L of this EA since the first day of the current month (profit + commission + swap)
void UpdateMonthPnl()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   g_month_closed = 0.0;
   if(!HistorySelect(StructToTime(dt), TimeCurrent())) return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      g_month_closed += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_SWAP);
   }
}

double FloatingPnl()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsOurPosition()) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

string ProfileName()
{
   if(InpIsPropFirm) return StringFormat("PROP %.2f%%", InpPropRiskPercent);
   switch(InpRiskProfile)
   {
      case PROFILE_AGGRESSIVE: return "AGGRESSIVE (3% -> 0.75%)";
      case PROFILE_MAXIMUM:    return "MAXIMUM (3% flat)";
      case PROFILE_CUSTOM:     return StringFormat("CUSTOM %.2f%%", InpRiskPercent);
   }
   return "STEADY (1%)";
}

//+------------------------------------------------------------------+
//| On-Chart HUD                                                     |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double room = RoomMoney();
   double next = MathMax(0.0, RiskMoneyForNextTrade());

   string status = IsHalted() ? StringFormat("HALTED until %s - %s", TimeToString(g_halt_until, TIME_DATE | TIME_MINUTES), g_halt_reason)
                              : "ACTIVE";
   string trend  = (g_trend > 0) ? "UP (longs only)" : (g_trend < 0) ? "DOWN (shorts only)" : "NONE (standing aside)";
   string floors = InpIsPropFirm ? StringFormat("daily %.2f | trailing %.2f%s", PropDailyFloor(), PropTrailingFloor(),
                                                 InpTrailLocksAtStart ? " (locked at start)" : "")
                                 : StringFormat("day stop %.2f", EntryFloor());
   if(InpIsPropFirm && InpPropTargetPct > 0.0)
      floors += g_target_done ? " | TARGET REACHED"
                              : StringFormat(" | target %.2f (+%.1f%%)", g_init_balance * (1.0 + InpPropTargetPct / 100.0), InpPropTargetPct);
   string clock  = g_clock_known ? StringFormat("server = New York %+dh = UTC%+d | US data hour %02d:00",
                                                g_srv_minus_ny, ServerUtcOffset(TimeCurrent()), SessionHourServer())
                                 : "waiting for the next gold reopen to read it";

   string hud = StringFormat(
      "======================================================\n"
      "   AEGIS v3.53  |  %s  |  %s\n"
      "======================================================\n"
      " Status:      %s\n"
      " Clock:       %s\n"
      " H4 trend:    %s  [stretch %.1f / max %.1f H4 ATR]\n"
      " Channel:     %s - %s   (M15 ATR %s)\n"
      "------------------------------------------------------\n"
      " Equity:      %.2f   (Balance %.2f)\n"
      " Day P/L:     %+.2f (%+.2f%%)\n"
      " Month P/L:   %+.2f closed  |  %+.2f open\n"
      " Floors:      %s\n"
      " Room left:   %.2f   Next unit risk: %.2f (%.2f%%)\n"
      " Units:       %d / %d\n"
      "------------------------------------------------------\n"
      " Last: %s\n"
      "======================================================",
      _Symbol, ProfileName(),
      status,
      clock,
      trend, g_stretch, TREND_MAX_STRETCH,
      Px(g_channel_lo), Px(g_channel_hi), Px(g_atr_value),
      eq, bal,
      eq - g_day_base, (g_day_base > 0.0) ? (eq - g_day_base) / g_day_base * 100.0 : 0.0,
      g_month_closed, FloatingPnl(),
      floors,
      room, next, (eq > 0.0) ? next / eq * 100.0 : 0.0,
      CountUnits(), MaxUnits(),
      g_last_event
   );
   Comment(hud);
}
//+------------------------------------------------------------------+
