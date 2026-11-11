//+------------------------------------------------------------------+
//| Trader.mqh - SevenWave v1.30 execution + multi-position management |
//| v1.30 whale extension (Growth): a probe that reaches +1.5R and its |
//|   add both aim for 5R and may run 72h (per-position time stop).    |
//|                                                                    |
//| Up to N concurrent positions (one per liquidity-pool trigger).     |
//| Each: market entry the moment its virtual stop is touched, hard    |
//| broker-side SL and TP, then (trend-tail style):                    |
//|   optional TP1 partial -> break-even;  ratchet trail on COMPLETED  |
//|   M1 bars once the best price reached actR (stop = best - trail);  |
//|   time stop.  R and trail distance are stored in the comment so a  |
//|   restarted EA re-adopts positions exactly.                        |
//| v1.20 whale pyramid (House Money Growth only): when a position     |
//|   ("probe") first reaches +1.5R, one ADD of the same size opens    |
//|   with its stop at the probe's entry and the probe's 3R target;    |
//|   the probe's stop is secured at break-even first.  Adds are       |
//|   tagged "<stream>+" and are re-linked to their probe on restart.  |
//| Prices quantised to the tick size; stop/freeze levels and filling  |
//| mode respected; latency/gap-safe entry (naked fill -> stops at     |
//| once -> close if price is already beyond the intended stop).       |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_TRADER_MQH
#define SEVENWAVE_TRADER_MQH

#include <Trade\Trade.mqh>

#define SW_MAXPOS 8

struct SwMgmt
  {
   double slK, tp1R, tp1Frac, beR, actR, trailK, tp2R;
   int    maxMin;
  };

struct SwPos
  {
   ulong    ticket;
   int      dir, stream;
   double   entry, R, trailDist, tp1Price, ext;
   bool     tp1Done;
   bool     isAdd;           // v1.20: a pyramid add (never pyramided itself)
   bool     added;           // v1.20: probe already had its one add decision
   int      maxMin;          // v1.30: per-position time stop (minutes); whales get a longer one
   datetime entryTime, lastM1;
  };

class CSwTrader
  {
public:
   string   sym;
   long     magic;
   CTrade   trade;
   SwMgmt   mg;
   SwPos    pos[SW_MAXPOS];
   int      np;
   int      logH;            // tester trade log (one row per closed position), INVALID_HANDLE when off
   string   names[8];
   int      whaleMaxMin;     // v1.30: time stop of whale positions (0 = whale extension off)
   double   whaleTrailMult;  // v1.31: whale trail / normal trail (1 = unchanged)

                     CSwTrader(void) : np(0), logH(INVALID_HANDLE), whaleMaxMin(0), whaleTrailMult(1.0) {}

   string            Tag(const SwPos &p) const
     {
      string nm = (p.stream >= 0 && p.stream < 8 && names[p.stream] != "") ? names[p.stream] : "?";
      return p.isAdd ? nm + "+" : nm;
     }

   //--- one row per CLOSED position from the deal history (exact P/L incl. partials, commission, swap)
   void              LogClosed(const SwPos &p)
     {
      if(logH == INVALID_HANDLE || p.ticket == 0)
         return;
      if(!HistorySelectByPosition(p.ticket))
         return;
      double net = 0.0, volIn = 0.0;
      datetime tIn = 0, tOut = 0;
      int outs = 0, winOuts = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong dl = HistoryDealGetTicket(i);
         if(dl == 0) continue;
         double v = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_COMMISSION) + HistoryDealGetDouble(dl, DEAL_SWAP);
         net += v;
         long entryType = HistoryDealGetInteger(dl, DEAL_ENTRY);
         datetime dt = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
         if(entryType == DEAL_ENTRY_IN) { tIn = dt; volIn = HistoryDealGetDouble(dl, DEAL_VOLUME); }
         else { tOut = MathMax(tOut, dt); outs++; if(v > 0.0) winOuts++; }
        }
      FileWrite(logH, (long)p.ticket, Tag(p), p.dir,
                TimeToString(tIn, TIME_DATE | TIME_SECONDS), TimeToString(tOut, TIME_DATE | TIME_SECONDS),
                DoubleToString(volIn, 2), DoubleToString(p.R, 2), DoubleToString(net, 2), outs, winOuts,
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
     }

   void              Init(const string s, long mgc, const SwMgmt &m)
     {
      sym = s; magic = mgc; mg = m; np = 0; logH = INVALID_HANDLE;
      trade.SetExpertMagicNumber(magic);
      trade.SetDeviationInPoints(100);
      trade.SetTypeFillingBySymbol(sym);
      trade.SetAsyncMode(false);
      trade.LogLevel(LOG_LEVEL_ERRORS);
      Sync();
     }

   double            Q(double price) const
     {
      double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(tick <= 0.0) return NormalizeDouble(price, dg);
      return NormalizeDouble(MathRound(price / tick) * tick, dg);
     }

   double            Tick(void) const
     {
      double t = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      return (t > 0.0) ? t : SymbolInfoDouble(sym, SYMBOL_POINT);
     }

   int               Count(void) { Sync(); return np; }

   //--- v1.20: slots are counted on probes only (adds ride inside their probe's slot, as in the research replay)
   int               Probes(void)
     {
      Sync();
      int k = 0;
      for(int i = 0; i < np; i++) if(!pos[i].isAdd) k++;
      return k;
     }

   int               Adds(void) const
     {
      int k = 0;
      for(int i = 0; i < np; i++) if(pos[i].isAdd) k++;
      return k;
     }

   //--- keep the state array identical to the broker's list of our positions (closed -> dropped, unknown -> adopted)
   void              Sync(void)
     {
      int k = 0;
      for(int i = 0; i < np; i++)
        {
         if(PositionSelectByTicket(pos[i].ticket))
            pos[k++] = pos[i];
         else
            LogClosed(pos[i]);                                     // closed by SL / TP / server
        }
      np = k;
      bool adopted = false;
      for(int i = PositionsTotal() - 1; i >= 0 && np < SW_MAXPOS; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         bool known = false;
         for(int q = 0; q < np; q++) if(pos[q].ticket == tk) { known = true; break; }
         if(!known)
           {
            Adopt(tk);
            adopted = true;
           }
        }
      if(adopted)
         LinkAdds();
     }

   //--- after a restart: a probe whose add is still open must never get a second one (the add's stop sits at the probe's entry)
   void              LinkAdds(void)
     {
      double tol = 3.0 * Tick() + 1e-9;
      for(int a = 0; a < np; a++)
        {
         if(!pos[a].isAdd || !PositionSelectByTicket(pos[a].ticket)) continue;
         double asl = PositionGetDouble(POSITION_SL);
         for(int p = 0; p < np; p++)
            if(!pos[p].isAdd && pos[p].dir == pos[a].dir && MathAbs(pos[p].entry - asl) <= tol)
               pos[p].added = true;
        }
     }

   void              Adopt(ulong tk)
     {
      if(!PositionSelectByTicket(tk)) return;
      SwPos p;
      p.ticket = tk;
      p.dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      p.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      p.stream = -1;
      p.isAdd = false; p.added = false;
      p.R = 0.0; p.trailDist = 0.0;
      string cm = PositionGetString(POSITION_COMMENT);           // "SW7 A R23.45 T31.27"  /  add: "SW7 A+ R35.10 T31.27"
      string parts[];
      int n = StringSplit(cm, ' ', parts);
      for(int i = 0; i < n; i++)
        {
         if(i == 1)
           {
            string tag = parts[i];
            int len = StringLen(tag);
            if(len > 1 && StringGetCharacter(tag, len - 1) == '+')
              {
               p.isAdd = true;
               tag = StringSubstr(tag, 0, len - 1);
              }
            for(int s = 0; s < 8; s++)
               if(names[s] != "" && names[s] == tag) { p.stream = s; break; }
            continue;
           }
         if(StringGetCharacter(parts[i], 0) == 'R') p.R = StringToDouble(StringSubstr(parts[i], 1));
         if(StringGetCharacter(parts[i], 0) == 'T') p.trailDist = StringToDouble(StringSubstr(parts[i], 1));
        }
      double sl = PositionGetDouble(POSITION_SL), tpx = PositionGetDouble(POSITION_TP);
      if(p.R <= 0.0) p.R = (sl > 0.0) ? MathAbs(p.entry - sl) : MathMax(1.0, p.entry * 0.004);
      if(p.trailDist <= 0.0) p.trailDist = p.R / mg.slK * mg.trailK;
      // v1.30: adds and extended probes (target beyond 4R) are whales -> the long time stop survives a restart
      p.maxMin = mg.maxMin;
      if(whaleMaxMin > 0 && (p.isAdd || (tpx > 0.0 && MathAbs(tpx - p.entry) > 4.0 * p.R)))
        {
         p.maxMin = whaleMaxMin;
         if(!p.isAdd)
           {
            p.added = true;
            p.trailDist *= whaleTrailMult;      // the probe's comment carries its original trail; adds carry the wide one
           }
        }
      p.tp1Price = p.entry + p.dir * mg.tp1R * p.R;
      p.tp1Done = (sl > 0.0 && p.dir * (sl - p.entry) >= 0.0);
      p.ext = p.entry;
      p.entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      p.lastM1 = iTime(sym, PERIOD_M1, 0);
      pos[np++] = p;
     }

   double            RespectStops(int d, double price, bool isStop)
     {
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      int lvl = (int)MathMax(SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL));
      double minD = (lvl + 1) * pt;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(d > 0) price = isStop ? MathMin(price, bid - minD) : MathMax(price, ask + minD);
      else      price = isStop ? MathMax(price, ask + minD) : MathMin(price, bid - minD);
      return Q(price);
     }

   //--- market entry.  stopDist/tp from the fill (probes), or absolute stop/target prices (adds: slAbs/tpAbs > 0)
   bool              Open(int d, double lots, double stopDist, double trailD, int strm, double p, string tag,
                          double slAbs = 0.0, double tpAbs = 0.0, bool isAdd = false, int maxMin = -1)
     {
      if(np >= SW_MAXPOS) return false;
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double px = (d > 0) ? ask : bid;
      double sl = RespectStops(d, Q(slAbs > 0.0 ? slAbs : px - d * stopDist), true);
      double tp = (tpAbs > 0.0) ? RespectStops(d, Q(tpAbs), false)
                                : ((mg.tp2R > 0.0) ? RespectStops(d, Q(px + d * mg.tp2R * stopDist), false) : 0.0);
      string cm = StringFormat("SW7 %s R%.2f T%.2f", tag, stopDist, trailD);
      bool ok = (d > 0) ? trade.Buy(lots, sym, 0.0, sl, tp, cm) : trade.Sell(lots, sym, 0.0, sl, tp, cm);
      uint rc = trade.ResultRetcode();
      if((!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED)) &&
         (rc == TRADE_RETCODE_INVALID_STOPS || rc == TRADE_RETCODE_INVALID_PRICE || rc == TRADE_RETCODE_PRICE_CHANGED ||
          rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_OFF))
        {
         ok = (d > 0) ? trade.Buy(lots, sym, 0.0, 0.0, 0.0, cm) : trade.Sell(lots, sym, 0.0, 0.0, 0.0, cm);
         rc = trade.ResultRetcode();
        }
      if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED))
        {
         PrintFormat("SevenWave: entry failed retcode=%d %s", rc, trade.ResultRetcodeDescription());
         return false;
        }
      ulong tk = 0;
      ulong deal = trade.ResultDeal();
      if(deal > 0 && HistoryDealSelect(deal))
         tk = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(tk == 0 || !PositionSelectByTicket(tk))
        {
         // fall back: newest position of ours not yet tracked
         datetime best = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong t2 = PositionGetTicket(i);
            if(t2 == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_MAGIC) != magic) continue;
            bool known = false;
            for(int q = 0; q < np; q++) if(pos[q].ticket == t2) { known = true; break; }
            if(!known && (datetime)PositionGetInteger(POSITION_TIME) >= best) { best = (datetime)PositionGetInteger(POSITION_TIME); tk = t2; }
           }
        }
      if(tk == 0 || !PositionSelectByTicket(tk))
         return false;
      SwPos q;
      q.ticket = tk; q.dir = d; q.stream = strm;
      q.entry = PositionGetDouble(POSITION_PRICE_OPEN);
      q.R = (slAbs > 0.0) ? MathMax(d * (q.entry - slAbs), Tick()) : stopDist;
      q.trailDist = trailD;
      q.tp1Price = q.entry + d * mg.tp1R * q.R;
      q.ext = q.entry; q.tp1Done = false;
      q.isAdd = isAdd; q.added = false;
      q.maxMin = (maxMin >= 0) ? maxMin : mg.maxMin;
      q.entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      q.lastM1 = iTime(sym, PERIOD_M1, 0);
      pos[np++] = q;
      //--- re-anchor SL/TP to the real fill price; never keep a naked or already-beaten position
      double want = Q(slAbs > 0.0 ? slAbs : q.entry - d * q.R);
      double nowPx = (d > 0) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      if(d * (nowPx - want) <= 0.0)
        {
         ClosePos(np - 1, "fill beyond intended stop");
         return false;
        }
      double tpWant = (tpAbs > 0.0) ? tpAbs : ((mg.tp2R > 0.0) ? q.entry + d * mg.tp2R * q.R : 0.0);
      double nsl = RespectStops(d, want, true);
      double ntp = (tpWant > 0.0) ? RespectStops(d, Q(tpWant), false) : 0.0;
      double tick = Tick();
      for(int attempt = 0; attempt < 3; attempt++)
        {
         if(!PositionSelectByTicket(tk)) break;
         if(MathAbs(nsl - PositionGetDouble(POSITION_SL)) < tick && MathAbs(ntp - PositionGetDouble(POSITION_TP)) < tick) break;
         if(trade.PositionModify(tk, nsl, ntp)) break;
         nsl = RespectStops(d, want, true);
         if(ntp > 0.0) ntp = RespectStops(d, Q(tpWant), false);
        }
      if(PositionSelectByTicket(tk) && PositionGetDouble(POSITION_SL) <= 0.0)
        {
         ClosePos(np - 1, "could not attach a stop loss");
         return false;
        }
      return true;
     }

   //--- v1.20 pyramid trigger: index of a probe whose price FIRST reached +atR (after its entry minute), or -1.
   //    Each probe gets exactly one add decision; a probe first seen beyond +maxR (gap, restart) is skipped.
   int               DueForAdd(double atR, double maxR)
     {
      double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      datetime now = TimeCurrent();
      for(int i = 0; i < np; i++)
        {
         if(pos[i].isAdd || pos[i].added || pos[i].R <= 0.0) continue;
         if(now < pos[i].entryTime - (pos[i].entryTime % 60) + 60) continue;
         double px = (pos[i].dir > 0) ? ask : bid;
         double run = pos[i].dir * (px - pos[i].entry) / pos[i].R;
         if(run < atR) continue;
         pos[i].added = true;
         if(run > maxR) continue;
         return i;
        }
      return -1;
     }

   //--- v1.30 whale extension: the probe's target moves to tpR and its time stop to whaleMaxMin (it reached +1.5R)
   void              ExtendWhale(int i, double tpR)
     {
      if(i < 0 || i >= np || whaleMaxMin <= 0 || !PositionSelectByTicket(pos[i].ticket)) return;
      int d = pos[i].dir;
      pos[i].maxMin = MathMax(pos[i].maxMin, whaleMaxMin);
      double ntp = RespectStops(d, Q(pos[i].entry + d * tpR * pos[i].R), false);
      double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(tp <= 0.0 || d * (ntp - tp) >= Tick())
         trade.PositionModify(pos[i].ticket, sl, ntp);
     }

   //--- v1.20: before an add, the probe's stop goes to at least break-even + beR, so the probe no longer carries risk
   void              SecureProbe(int i)
     {
      if(i < 0 || i >= np || !PositionSelectByTicket(pos[i].ticket)) return;
      int d = pos[i].dir;
      double be = RespectStops(d, Q(pos[i].entry + d * mg.beR * pos[i].R), true);
      double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(d * (be - pos[i].entry) >= 0.0 && (sl <= 0.0 || d * (be - sl) >= Tick()))
         trade.PositionModify(pos[i].ticket, be, tp);
     }

   void              ClosePos(int i, const string why)
     {
      if(i < 0 || i >= np) return;
      if(PositionSelectByTicket(pos[i].ticket))
         trade.PositionClose(pos[i].ticket);
      if(!PositionSelectByTicket(pos[i].ticket))
         LogClosed(pos[i]);
      for(int k = i; k < np - 1; k++) pos[k] = pos[k + 1];
      np--;
     }

   void              CloseAll(const string why)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_MAGIC) != magic) continue;
         trade.PositionClose(tk);
        }
      for(int i = 0; i < np; i++)
         if(!PositionSelectByTicket(pos[i].ticket))
            LogClosed(pos[i]);
      Print("SevenWave: flatten - ", why);
      np = 0;
     }

   //--- every tick
   void              ManageAll(void)
     {
      Sync();
      double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double tick = Tick();
      datetime m1 = iTime(sym, PERIOD_M1, 0);
      datetime bt = iTime(sym, PERIOD_M1, 1);
      double h1b = iHigh(sym, PERIOD_M1, 1), l1b = iLow(sym, PERIOD_M1, 1), c1b = iClose(sym, PERIOD_M1, 1);
      for(int i = np - 1; i >= 0; i--)
        {
         if(!PositionSelectByTicket(pos[i].ticket)) continue;
         int d = pos[i].dir;
         double px = (d > 0) ? bid : ask;
         double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP), vol = PositionGetDouble(POSITION_VOLUME);
         //--- optional TP1 partial + break-even
         if(!pos[i].tp1Done && mg.tp1Frac > 0.0 && d * (px - pos[i].tp1Price) >= 0.0)
           {
            double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            double part = MathFloor(vol * mg.tp1Frac / step) * step;
            if(part >= vmin && vol - part >= vmin - 1e-9)
               trade.PositionClosePartial(pos[i].ticket, NormalizeDouble(part, (int)MathMax(0, MathRound(-MathLog10(step)))));
            pos[i].tp1Done = true;
            if(PositionSelectByTicket(pos[i].ticket))
              {
               double be = RespectStops(d, Q(pos[i].entry + d * mg.beR * pos[i].R), true);
               sl = PositionGetDouble(POSITION_SL); tp = PositionGetDouble(POSITION_TP);
               if(d * (be - sl) >= tick) trade.PositionModify(pos[i].ticket, be, tp);
              }
           }
         //--- completed-M1-bar ratchet (never credits the fill minute)
         if(m1 != pos[i].lastM1)
           {
            pos[i].lastM1 = m1;
            if(bt >= pos[i].entryTime - (pos[i].entryTime % 60) + 60)
              {
               double fav = (d > 0) ? h1b : l1b + (ask - bid);
               double cl = c1b + ((d > 0) ? 0.0 : (ask - bid));
               if(d * (fav - pos[i].ext) > 0.0) pos[i].ext = fav;
               if(pos[i].trailDist > 0.0 && d * (pos[i].ext - pos[i].entry) >= mg.actR * pos[i].R && PositionSelectByTicket(pos[i].ticket))
                 {
                  double lvl = RespectStops(d, Q(pos[i].ext - d * pos[i].trailDist), true);
                  sl = PositionGetDouble(POSITION_SL); tp = PositionGetDouble(POSITION_TP);
                  if(d * (lvl - sl) >= tick && d * (cl - lvl) > 0.0)
                     trade.PositionModify(pos[i].ticket, lvl, tp);
                 }
              }
           }
         //--- time stop (per position: whales keep a longer one)
         if(pos[i].maxMin > 0 && TimeCurrent() - pos[i].entryTime >= (datetime)(pos[i].maxMin * 60))
            ClosePos(i, "time stop");
        }
     }
  };

#endif
