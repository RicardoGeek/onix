//+------------------------------------------------------------------+
//| RiskEngine.mqh - SevenWave v1.10 dual-mode PORTFOLIO risk engine   |
//|                                                                    |
//| Floors (re-evaluated every tick):                                  |
//|   daily : max(day-start balance, day-start equity) * (1 - daily%)  |
//|           (day = broker server day, the clock prop firms use)      |
//|   total : high-water mark of max(balance, equity) * (1 - max%)     |
//| Portfolio never-breach budget: the CURRENT risk of every open      |
//|   position (loss if its stop is hit now; 0 once the stop locks     |
//|   profit) plus the new trade, +25% slippage cushion, may use at    |
//|   most 15% (Prop) / 50% (Growth) of the smaller of today's room    |
//|   and the trailing room.  15% keeps the expected growth of the     |
//|   room positive near a floor (Kelly-safe recovery, never a freeze) |
//|   and no combination of stops can breach either limit.             |
//| Breakers: equity within 20% of the daily budget, or a FRESH slide  |
//|   to within 10% of the total budget -> flatten, stand down today.  |
//| Prop consistency lock: once today's gain reaches 80% of the daily  |
//|   loss limit (2.4% with the 3% default) the day is banked: flatten |
//|   and stand down, so no single day can dominate the profit (prop   |
//|   "best day <= 30% of the target" rules).                          |
//| Lots: max(OrderCalcProfit, tick formula, contract floor) loss per  |
//|   lot (immune to 10x tick-value bugs), margin capped at 85% free.  |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_RISKENGINE_MQH
#define SEVENWAVE_RISKENGINE_MQH

#ifndef SW_GROWTH_TOT_FRAC
#define SW_GROWTH_TOT_FRAC 0.25   // v1.33: Kelly-safe Growth share of the trailing room (0.5 froze at the 30% floor in honest 2018-23)
#endif

enum ENUM_SW_MODE
  {
   SW_PROP_FIRM = 0,          // Prop Firm (protect the account, consistency lock)
   SW_HOUSE_MONEY_GROWTH = 1  // House Money Growth (compound fast)
  };

class CSwRisk
  {
public:
   string   sym;
   long     magic;
   int      mode;
   double   riskPct, dailyPct, maxPct;
   double   dayRef, hwm, startBal;
   long     dayKey;
   bool     halted;
   string   haltWhy;
   string   gvPrefix;
   double   roomFrac;        // share of TODAY's remaining room the WHOLE portfolio may risk
   double   roomFracTot;     // share of the TRAILING room (Kelly-safe near the trailing floor)
   bool     dayStartedAboveTotalTrip;

   void              Init(const string s, int md, double rp, double dd, double mdd, long mgc)
     {
      sym = s; mode = md; magic = mgc;
      riskPct  = (rp  > 0.0) ? rp  : (md == SW_PROP_FIRM ? 0.5 : 1.0);
      dailyPct = (dd  > 0.0) ? dd  : (md == SW_PROP_FIRM ? 3.0 : 10.0);
      maxPct   = (mdd > 0.0) ? mdd : (md == SW_PROP_FIRM ? 6.0 : 30.0);
      gvPrefix = StringFormat("SW7_%I64d_%I64d_", AccountInfoInteger(ACCOUNT_LOGIN), magic);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
      hwm = MathMax(bal, eq);
      startBal = bal;
      if(GlobalVariableCheck(gvPrefix + "hwm"))   hwm = MathMax(hwm, GlobalVariableGet(gvPrefix + "hwm"));
      if(GlobalVariableCheck(gvPrefix + "start")) startBal = GlobalVariableGet(gvPrefix + "start");
      else GlobalVariableSet(gvPrefix + "start", startBal);
      dayKey = -1; dayRef = MathMax(bal, eq); halted = false; haltWhy = "";
      // Prop: 15% of the room (positive expected growth of the room near the trailing floor -> recovery, not freeze);
      // Growth: 50% of today's room
      roomFrac = (md == SW_PROP_FIRM) ? 0.15 : 0.5;
      // share of the TRAILING room (Kelly-safe near the floor): Prop 0.15, Growth 0.25 since v1.33 (MT5 $10k 1%: 2018-23 froze in
      // Aug 2022 at 0.5, +$53.8k at 0.25; 2024-26 +$292k at 0.5, +$280k at 0.25)
      roomFracTot = (md == SW_PROP_FIRM) ? 0.15 : SW_GROWTH_TOT_FRAC;
      dayStartedAboveTotalTrip = true;
     }

   double            FloorDay(void) const { return dayRef * (1.0 - dailyPct / 100.0); }
   double            FloorTot(void) const { return hwm * (1.0 - maxPct / 100.0); }
   double            DDPct(void) const { double eq = AccountInfoDouble(ACCOUNT_EQUITY); return (hwm > 0) ? (hwm - eq) / hwm * 100.0 : 0.0; }
   double            DayPnlPct(void) const { double eq = AccountInfoDouble(ACCOUNT_EQUITY); return (dayRef > 0) ? (eq - dayRef) / dayRef * 100.0 : 0.0; }
   double            LockPct(void) const { return (mode == SW_PROP_FIRM) ? 0.8 * dailyPct : 0.0; }

   //--- every tick; returns true when the account must be flattened now
   bool              OnTick(void)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
      long key = (long)(TimeCurrent() / 86400);
      if(key != dayKey)
        {
         dayKey = key;
         dayRef = MathMax(bal, eq);
         halted = false; haltWhy = "";
         double ft0 = FloorTot();
         // the trailing breaker only guards FRESH intraday slides; a day that opens near the floor is handled by
         // the room-based sizing (tiny, recovering risk) instead of freezing the account forever
         dayStartedAboveTotalTrip = (eq > ft0 + 0.1 * (hwm - ft0));
        }
      double m = MathMax(bal, eq);
      if(m > hwm)
        {
         hwm = m;
         GlobalVariableSet(gvPrefix + "hwm", hwm);
        }
      if(halted)
         return false;
      double fd = FloorDay(), ft = FloorTot();
      if(eq <= fd + 0.2 * (dayRef - fd))
        {
         halted = true; haltWhy = StringFormat("daily breaker: equity %.2f near daily floor %.2f", eq, fd);
         return true;
        }
      if(dayStartedAboveTotalTrip && eq <= ft + 0.1 * (hwm - ft))
        {
         halted = true; haltWhy = StringFormat("total breaker: equity %.2f near trailing floor %.2f", eq, ft);
         return true;
        }
      double lock = LockPct();
      if(lock > 0.0 && eq - dayRef >= dayRef * lock / 100.0)
        {
         halted = true; haltWhy = StringFormat("consistency lock: day banked at +%.2f%%", (eq - dayRef) / dayRef * 100.0);
         return true;
        }
      return false;
     }

   double            LossPerLot(int dir, double entry, double sl) const
     {
      double dist = MathAbs(entry - sl);
      double pl = 0.0;
      ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcProfit(t, sym, 1.0, entry, sl, pl))
         pl = 0.0;
      double a = MathAbs(pl);
      double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tv <= 0.0) tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double b = (tick > 0.0 && tv > 0.0) ? dist / tick * tv : 0.0;
      double c = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) * dist;
      return MathMax(a, MathMax(b, c));
     }

   //--- current risk of all our open positions (loss if every stop were hit now; locked-profit stops count 0)
   double            OpenRisk(void)
     {
      double total = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
         double vol = PositionGetDouble(POSITION_VOLUME);
         if(sl <= 0.0) { total += vol * LossPerLot(d, op, op - d * op * 0.01); continue; }   // no stop: assume 1%
         if(d * (op - sl) > 0.0)
            total += vol * LossPerLot(d, op, sl);
        }
      return total;
     }

   //--- lots for a stop distance; 0 = do not trade (with reason)
   double            Lots(int dir, double entry, double sl, double weight, string &why)
     {
      why = "";
      if(halted) { why = "halted: " + haltWhy; return 0.0; }
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double roomDay = eq - FloorDay();
      double roomTot = eq - FloorTot();
      if(roomDay <= 0.0 || roomTot <= 0.0) { why = "no drawdown room"; return 0.0; }
      double budget = MathMin(roomDay * roomFrac, roomTot * roomFracTot) / 1.25 - OpenRisk();
      if(budget <= 0.0) { why = "portfolio risk budget used"; return 0.0; }
      double risk = MathMin(eq * riskPct / 100.0 * weight, budget);
      double lpl = LossPerLot(dir, entry, sl) + SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) * 0.10;  // stop slippage
      if(lpl <= 0.0) { why = "loss-per-lot unavailable"; return 0.0; }
      double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double vlim = SymbolInfoDouble(sym, SYMBOL_VOLUME_LIMIT);
      if(step <= 0.0) step = vmin;
      double lots = MathFloor(risk / lpl / step) * step;
      if(lots < vmin)
        {
         if(vmin * lpl * 1.25 <= budget)
            lots = vmin;
         else { why = StringFormat("min lot risk %.2f exceeds safe budget %.2f", vmin * lpl, budget); return 0.0; }
        }
      if(vmax > 0.0) lots = MathMin(lots, vmax);
      if(vlim > 0.0)
        {
         double used = 0.0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong tk = PositionGetTicket(i);
            if(tk != 0 && PositionGetString(POSITION_SYMBOL) == sym) used += PositionGetDouble(POSITION_VOLUME);
           }
         lots = MathMin(lots, MathFloor((vlim - used) / step) * step);
         if(lots < vmin) { why = "symbol volume limit reached"; return 0.0; }
        }
      //--- margin: always evaluate the market deal type (pending types return 0 margin on some prop feeds)
      double price = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      double mrg = 0.0;
      ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(OrderCalcMargin(t, sym, lots, price, mrg) && mrg > 0.0 && mrg > 0.85 * free)
        {
         lots = MathFloor(lots * (0.85 * free / mrg) / step) * step;
         if(lots < vmin) { why = "not enough free margin"; return 0.0; }
        }
      int dg = (int)MathMax(0, MathRound(-MathLog10(step)));
      return NormalizeDouble(lots, dg);
     }
  };

#endif

