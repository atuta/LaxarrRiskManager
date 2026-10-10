//+------------------------------------------------------------------+
//|                                TradingPanelPropChallenge.mqh     |
//|  Out-of-line CTradingPanelDialog method bodies (see TradingPanel |
//|  .mq5 for the class declaration and split rationale) for the     |
//|  prop-firm challenge link: the active challenge's rules arrive    |
//|  with the normal Sync (GET /mt5/last-sync/), and everything      |
//|  below enforces them LOCALLY against live equity — no polling,   |
//|  no WebRequest (periodic WebRequest is what made the panel feel  |
//|  sticky; see the top of TradingPanel.mq5).                       |
//|                                                                  |
//|  - Daily loss: from the balance at the firm's day start (its     |
//|    reset timezone, sent by the backend as a UTC instant) down to |
//|    current equity, vs % of the account size or of that day-start |
//|    balance.                                                      |
//|  - Maximum loss: equity vs the floor — account size minus the    |
//|    max loss (static), or the highest balance minus it (trailing).|
//|  - Execute is blocked when this trade's stop-loss risk exceeds   |
//|    what's left under either limit.                               |
//|  - Optionally (ChallengeAutoClose) closes every position once    |
//|    ChallengeAutoCloseAtPercent of a limit is used, before the    |
//|    firm's own limit is hit.                                      |
//+------------------------------------------------------------------+
#ifndef TRADINGPANEL_PROPCHALLENGE_MQH
#define TRADINGPANEL_PROPCHALLENGE_MQH

//--- Reads the challenge_* fields of a successful last-sync response (see
//--- ea_challenge_payload on the backend). An older backend sends none of
//--- them: the challenge link then simply stays off.
void CTradingPanelDialog::ParseChallengeFields(const string response)
{
   string v;
   if(!JsonExtractString(response, "challenge_active", v) || v != "true")
   {
      if(m_challengeActive && EnableLogging) Print("Prop challenge: no active challenge on this account any more.");
      m_challengeActive = false;
      return;
   }

   m_challengeActive = true;
   m_challengeLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   JsonExtractString(response, "challenge_name", m_challengeName);
   if(JsonExtractString(response, "challenge_account_size", v))    m_challengeAccountSize = StringToDouble(v);
   if(JsonExtractString(response, "challenge_daily_loss_pct", v))  m_challengeDailyLossPct = StringToDouble(v);
   if(JsonExtractString(response, "challenge_daily_basis", v))     m_challengeDailyFromDayStart = (v == "day_start");
   if(JsonExtractString(response, "challenge_max_loss_amount", v)) m_challengeMaxLossAmount = StringToDouble(v);
   if(JsonExtractString(response, "challenge_max_loss_type", v))   m_challengeTrailing = (v == "trailing");
   if(JsonExtractString(response, "challenge_peak_balance", v))    m_challengePeakBalance = StringToDouble(v);
   if(JsonExtractString(response, "challenge_day_start_utc", v))   m_challengeDayStartUtc = (datetime)StringToInteger(v);
   m_challengeCacheTime = 0; // recompute the day-start balance with the fresh rules

   if(m_challengeAccountSize <= 0.0 || m_challengeMaxLossAmount <= 0.0 || m_challengeDayStartUtc <= 0)
   {
      Print("Prop challenge: incomplete rules in the sync response - challenge protection is off until the next Sync.");
      m_challengeActive = false;
      return;
   }
   if(EnableLogging)
      Print("Prop challenge linked: ", m_challengeName, " (daily ", DoubleToString(m_challengeDailyLossPct, 2),
            "% ", (m_challengeDailyFromDayStart ? "of day-start balance" : "of account size"),
            ", max loss ", DoubleToString(m_challengeMaxLossAmount, 2), (m_challengeTrailing ? " trailing" : " static"), ")");
}

//--- The firm's current trading day start, as trade-server time (what
//--- HistorySelect/DEAL_TIME use). The backend sends the UTC instant at
//--- Sync time; between Syncs it's rolled forward 24h at a time here.
datetime CTradingPanelDialog::ChallengeDayStartServer()
{
   datetime nowUtc = TimeGMT();
   while(nowUtc - m_challengeDayStartUtc >= 86400)
   {
      m_challengeDayStartUtc += 86400;
      m_challengeCacheTime = 0; // new trading day: new day-start balance
   }
   return m_challengeDayStartUtc + (TimeTradeServer() - TimeGMT());
}

//--- Balance at the firm's day start = current balance minus everything
//--- trading has added or taken since then (profit, swap, commission and
//--- fees of every trade deal — opening commissions change the balance
//--- too). Cached for 30s: the balance and that realized sum only move
//--- together, on a fill, so the difference is stable between fills.
double CTradingPanelDialog::ChallengeDayStartBalance()
{
   datetime dayStart = ChallengeDayStartServer();
   if(m_challengeCacheTime > 0 && TimeCurrent() - m_challengeCacheTime < 30)
      return m_challengeDayStartBalance;

   double realized = 0.0;
   if(HistorySelect(dayStart, TimeTradeServer() + 60))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue; // skip deposits/credits
         realized += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                   + HistoryDealGetDouble(ticket, DEAL_SWAP)
                   + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                   + HistoryDealGetDouble(ticket, DEAL_FEE);
      }
   }
   m_challengeDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - realized;
   m_challengeCacheTime = TimeCurrent();
   return m_challengeDayStartBalance;
}

//--- Live headroom under both limits, in account currency (can go
//--- negative once a limit is exceeded). Also returns each limit's size
//--- so callers can work out "% used". False when no challenge is linked.
bool CTradingPanelDialog::ComputeChallengeHeadroom(double &dailyLeft, double &dailyLimit,
                                                    double &overallLeft, double &overallLimit)
{
   if(!m_challengeActive) return false;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayStartBalance = ChallengeDayStartBalance();

   dailyLimit = (m_challengeDailyFromDayStart ? dayStartBalance : m_challengeAccountSize)
              * m_challengeDailyLossPct / 100.0;
   double dailyUsed = MathMax(0.0, dayStartBalance - equity);
   dailyLeft = dailyLimit - dailyUsed;

   if(m_challengeTrailing && balance > m_challengePeakBalance)
      m_challengePeakBalance = balance; // trailing floor follows new highs
   double floorBalance = (m_challengeTrailing ? m_challengePeakBalance : m_challengeAccountSize)
                       - m_challengeMaxLossAmount;
   overallLimit = m_challengeMaxLossAmount;
   overallLeft = equity - floorBalance;
   return true;
}

//--- Part of CheckRiskLimitsBlocking (see TradingPanelGuardrails.mqh):
//--- "" when clear, else why this trade would put the challenge at risk.
//--- The trade's own risk is its stop-loss loss — the same "potential
//--- loss" figure the Execute confirmation shows (MoneyOf(ROW_SL)).
string CTradingPanelDialog::CheckChallengeBlocking()
{
   double dailyLeft = 0.0, dailyLimit = 0.0, overallLeft = 0.0, overallLimit = 0.0;
   if(!ComputeChallengeHeadroom(dailyLeft, dailyLimit, overallLeft, overallLimit)) return "";

   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   double tradeRisk = MathAbs(ActivePanel().MoneyOf(ROW_SL));

   if(dailyLeft <= 0.0)
      return "Prop challenge: today's loss limit is already used up - no new trades until the firm's next trading day.";
   if(overallLeft <= 0.0)
      return "Prop challenge: the maximum loss limit is already reached.";
   if(tradeRisk > dailyLeft)
      return "Prop challenge: this trade risks " + DoubleToString(tradeRisk, 2) + " " + cur +
             " at its stop loss, more than the " + DoubleToString(dailyLeft, 2) + " " + cur +
             " left under today's loss limit. Reduce the size or tighten the stop.";
   if(tradeRisk > overallLeft)
      return "Prop challenge: this trade risks " + DoubleToString(tradeRisk, 2) + " " + cur +
             " at its stop loss, more than the " + DoubleToString(overallLeft, 2) + " " + cur +
             " left before the maximum loss limit.";
   return "";
}

//--- Every tick (see OnTick), independent of Execute — floating losses can
//--- eat a limit with no click involved. Only acts when ChallengeAutoClose
//--- is on and positions are open; closes them all once either limit is
//--- ChallengeAutoCloseAtPercent used, so the firm's own limit isn't hit.
//--- Idempotent: nothing left to close afterwards.
void CTradingPanelDialog::EnforceChallengeLimits()
{
   if(!ChallengeAutoClose || !m_challengeActive || PositionsTotal() == 0) return;

   double dailyLeft = 0.0, dailyLimit = 0.0, overallLeft = 0.0, overallLimit = 0.0;
   if(!ComputeChallengeHeadroom(dailyLeft, dailyLimit, overallLeft, overallLimit)) return;

   double dailyUsedPct   = dailyLimit   > 0.0 ? (dailyLimit - dailyLeft) / dailyLimit * 100.0 : 0.0;
   double overallUsedPct = overallLimit > 0.0 ? (overallLimit - overallLeft) / overallLimit * 100.0 : 0.0;
   double threshold = MathMax(1.0, MathMin(ChallengeAutoCloseAtPercent, 100.0));
   if(dailyUsedPct < threshold && overallUsedPct < threshold) return;

   Print("Prop challenge protection: ", (dailyUsedPct >= threshold ? "daily" : "maximum"),
         " loss limit ", DoubleToString(MathMax(dailyUsedPct, overallUsedPct), 1),
         "% used (auto-close at ", DoubleToString(threshold, 1), "%) - closing all open positions.");
   CloseAllPositions();
}

//--- The two spare lines of the risk cards (see UpdateRiskLimitsLabel):
//--- what's left under each challenge limit, live. Refreshed from OnTimer
//--- (local only) and after each Sync; turns red past 70% used.
void CTradingPanelDialog::UpdateChallengeCardLines()
{
   //--- Before the first successful Sync, card 0's three lines carry the
   //--- loading/error message (see UpdateRiskLimitsLabel) — leave them be.
   if(!m_riskParamsLoaded) return;
   double dailyLeft = 0.0, dailyLimit = 0.0, overallLeft = 0.0, overallLimit = 0.0;
   if(!ComputeChallengeHeadroom(dailyLeft, dailyLimit, overallLeft, overallLimit))
   {
      m_riskCardLine[0][2].Text("");
      m_riskCardLine[2][2].Text("");
      return;
   }
   m_riskCardLine[0][2].Text("Prop day left: " + DoubleToString(MathMax(0.0, dailyLeft), 2));
   m_riskCardLine[2][2].Text("Prop max left: " + DoubleToString(MathMax(0.0, overallLeft), 2));
   m_riskCardLine[0][2].Color(dailyLeft < dailyLimit * 0.3 ? clrRed : C'90,90,90');
   m_riskCardLine[2][2].Color(overallLeft < overallLimit * 0.3 ? clrRed : C'90,90,90');
}

#endif // TRADINGPANEL_PROPCHALLENGE_MQH
