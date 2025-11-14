#pragma once
double g_varAlertThrottleRatioLevel=0.70;
double g_varAlertOpenRiskPercentEquity=0.40;
datetime g_lastVaRAlert=0;
int g_varAlertCooldownMinutes=15;
void CheckVaRAlerts(double throttleRatio,double openRiskCurrency,double equity){datetime now=TimeCurrent();if(g_lastVaRAlert!=0 && now-g_lastVaRAlert<g_varAlertCooldownMinutes*60) return;bool trigger=false;string msg="VaR OK";double openRiskPct=(equity>0)?(openRiskCurrency/equity*100.0):0.0;if(throttleRatio>g_varAlertThrottleRatioLevel){trigger=true;msg="VaR Throttle Ratio Breach: "+DoubleToString(throttleRatio,2);}else if(openRiskPct>g_varAlertOpenRiskPercentEquity){trigger=true;msg="VaR OpenRisk% Equity Breach: "+DoubleToString(openRiskPct,2)+"%";}if(trigger){Alert(msg);Print(msg);g_lastVaRAlert=now;}