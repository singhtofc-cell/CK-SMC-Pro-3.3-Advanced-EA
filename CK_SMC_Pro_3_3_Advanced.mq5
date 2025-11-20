//+------------------------------------------------------------------+
//|  CK Sniper SMC Scanner EA  –  BUILD-5430 PATCHED  v2.30       |
//|  (c) singhtofc-cell 2025 – M5 default                            |
//+------------------------------------------------------------------+
#property strict
#property version   "2.30"
#property description "CK Sniper SMC – build-5430 clean – M5"
#property copyright   "singhtofc-cell 2025"

#include <Trade\Trade.mqh>
CTrade Trade;

#define  MAX_SYMBOLS   32
#define  MAX_POIS      10
#define  MAX_DASH_OBJ  500

//--------------------------- INPUTS ---------------------------------
input string Inp_SymbolList   = "EURUSD;GBPUSD;USDJPY;AUDUSD;USDCAD;USDCHF;NZDUSD;EURJPY;EURGBP;XAUUSD";
input bool   Inp_SuffixAuto   = true;
input string Inp_SuffixCand   = "c;m;.c;.m;_c;_m";
input bool   Inp_TradeChart   = true;
input bool   Inp_ScanAuto     = true;

input long   Inp_Magic        = 99011000;
input double Inp_RiskPct      = 0.5;
input int    Inp_MaxPos       = 1;
input double Inp_MaxSpread    = 3.0;
input double Inp_SLpips       = 20.0;
input double Inp_MinSLpips    = 8.0;
input double Inp_TP1RR        = 1.5;
input double Inp_TP2RR        = 3.0;
input int    Inp_TP1Pct       = 50;
input int    Inp_TP2Pct       = 100;
input double Inp_BreakEvenRR  = 1.0;

input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M5;
input bool   Inp_ReqBias      = true;
input bool   Inp_MultiTF      = true;
input double Inp_EntryDist    = 10.0;
input double Inp_MinFVG       = 2.0;
input int    Inp_MaxAgeBars   = 150;
input bool   Inp_UseFVG       = true;
input bool   Inp_UseOB        = true;

input bool   Inp_PyrOn        = true;
input int    Inp_PyrMaxLvl    = 3;
input double Inp_PyrAddRR     = 0.5;
input double Inp_PyrMult      = 0.5;
input bool   Inp_PyrMoveSL    = true;

input bool   Inp_TrailOn      = false;
input double Inp_TrailStartRR = 2.0;
input double Inp_TrailStep    = 5.0;

input bool   Inp_LogCSV       = true;
input string Inp_LogPrefix    = "CK_Sniper_Log";
input bool   Inp_DashOn       = true;
input int    Inp_DashX        = 10;
input int    Inp_DashY        = 30;
input int    Inp_FontSize     = 9;
input color  Inp_DashBG       = clrBlack;
input color  Inp_DashTxt      = clrWhite;
input color  Inp_DashGain     = clrLime;
input color  Inp_DashLoss     = clrRed;
input bool   Inp_EnTrading    = true;

//--------------------------- ENUMS / STRUCTS --------------------------
enum BiasDir { BiasNone=0, BiasBull=1, BiasBear=2 };
enum POIType { POI_FVG=0, POI_OB=1 };

struct POI_Info {
   double price;  BiasDir dir;  POIType type;  datetime time;  int bar;
   double strength;  bool valid;  bool active;  double high;  double low;  string desc;
};
struct TPSLLevels {
   double entry, sl, tp1, tp2, risk, reward, lots;  bool valid;
};
struct SymbolData {
   string name, sym, asset;  ulong magic;  bool tradable;
   BiasDir htf, ltf;
   POI_Info poi[MAX_POIS];  int poi_cnt;
   datetime last_scan, last_entry;
   bool pyr_on;  BiasDir pyr_dir;
   double pyr_entry, pyr_sl, pyr_lots;  int pyr_lvl;
   struct PyrLvl { int lvl; double entry, rr, mult; bool fill; ulong ticket; } pyr[5];
   int pos_cnt, pen_cnt;  double run_pl;  int win, loss, trades;
};
SymbolData g_sym[32];  int g_cnt=0;
string g_log="";  datetime g_last_up=0, g_last_scan=0;

//--------------------------- UTILS -----------------------------------
double PipVal(const string s){
   int d=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   return (d==5 || d==3) ? SymbolInfoDouble(s,SYMBOL_POINT)*10.0 : SymbolInfoDouble(s,SYMBOL_POINT);
}
double P2P(const string s,const double pips){ return pips*PipVal(s); }
double P2R(const string s,const double price){ return PipVal(s)>0 ? price/PipVal(s) : 0; }
double Spread(const string s){ return P2R(s,SymbolInfoDouble(s,SYMBOL_ASK)-SymbolInfoDouble(s,SYMBOL_BID)); }
bool IsMagic(ulong m){ return m>=Inp_Magic && m<Inp_Magic+1000; }
string BiasStr(BiasDir b){ return b==BiasBull?"BULL":b==BiasBear?"BEAR":"NONE"; }
string AssetType(const string s){
   string t=s; StringToUpper(t);
   if(StringFind(t,"XAU")>=0||StringFind(t,"XAG")>=0) return "METALS";
   if(StringFind(t,"US30")>=0||StringFind(t,"NAS")>=0) return "INDICES";
   if(StringFind(t,"BTC")>=0||StringFind(t,"ETH")>=0||StringFind(t,"XRP")>=0) return "CRYPTO";
   return "FOREX";
}

//--------------------------- LOG -------------------------------------
void LogEvent(string evt,string sym="",string note=""){
   if(!Inp_LogCSV) return;
   if(g_log=="") g_log=Inp_LogPrefix+"_"+TimeToString(TimeCurrent(),TIME_DATE)+".csv";
   int h=FileOpen(g_log,FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWrite(h,"time","event","symbol","asset","bias","note");
   FileSeek(h,0,SEEK_END);
   string a="UNKNOWN",b="NONE";
   for(int i=0;i<g_cnt;i++) if(g_sym[i].sym==sym){ a=g_sym[i].asset; b=BiasStr(g_sym[i].htf); break; }
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),evt,sym,a,b,note);
   FileClose(h);
   Print("📝 "+evt+" | "+sym+" | "+note);
}

//--------------------------- BIAS ------------------------------------
BiasDir HTFbias(const string s){
   MqlRates r[]; ArraySetAsSeries(r,true);
   int n=(int)CopyRates(s,PERIOD_H1,0,30,r); if(n<20) return BiasNone;
   int hh=0,ll=0; for(int i=1;i<20;i++){ if(r[i].high>r[i+1].high) hh++; if(r[i].low<r[i+1].low) ll++; }
   double ma=0; for(int i=0;i<10;i++) ma+=r[i].close; ma/=10.0;
   bool above=r[0].close>ma, below=r[0].close<ma;
   if(hh>ll+3&&above) return BiasBull; if(ll>hh+3&&below) return BiasBear; return BiasNone;
}
BiasDir LTFbias(const string s){
   MqlRates r[]; ArraySetAsSeries(r,true);
   int n=(int)CopyRates(s,InpSignalTF,0,20,r); if(n<10) return BiasNone;
   int bull=0,bear=0; for(int i=0;i<10;i++){ if(r[i].close>r[i].open) bull++; else if(r[i].close<r[i].open) bear++; }
   if(bull>bear+2) return BiasBull; if(bear>bull+2) return BiasBear; return BiasNone;
}

//--------------------------- POI -------------------------------------
int DetectFVG(const string s,POI_Info &arr[],int max_poi){
   if(!Inp_UseFVG) return 0;
   MqlRates r[]; ArraySetAsSeries(r,true);
   int n=(int)CopyRates(s,InpSignalTF,0,100,r); if(n<20) return 0;
   int cnt=0; string asset=AssetType(s);
   double gap_min=Inp_MinFVG; if(asset=="METALS") gap_min*=2; else if(asset=="INDICES") gap_min*=5; else if(asset=="CRYPTO") gap_min*=3;
   for(int i=2;i<n-2&&cnt<max_poi;i++){
      if(i>Inp_MaxAgeBars) continue;
      if(r[i].low>r[i+2].high){
         double gap=P2R(s,r[i].low-r[i+2].high);
         if(gap>=gap_min){
            POI_Info &p=arr[cnt++];
            p.price=(r[i].low+r[i+2].high)/2.0; p.high=r[i].low; p.low=r[i+2].high;
            p.dir=BiasBull; p.type=POI_FVG; p.time=r[i].time; p.bar=i;
            p.strength=gap*10; p.valid=p.active=true; p.desc="Bull FVG "+DoubleToString(gap,1)+"p";
         }
      }
      if(cnt<max_poi&&r[i].high<r[i+2].low){
         double gap=P2R(s,r[i+2].low-r[i].high);
         if(gap>=gap_min){
            POI_Info &p=arr[cnt++];
            p.price=(r[i].high+r[i+2].low)/2.0; p.high=r[i+2].low; p.low=r[i].high;
            p.dir=BiasBear; p.type=POI_FVG; p.time=r[i].time; p.bar=i;
            p.strength=gap*10; p.valid=p.active=true; p.desc="Bear FVG "+DoubleToString(gap,1)+"p";
         }
      }
   }
   return cnt;
}
int DetectOB(const string s,POI_Info &arr[],int start,int max_poi){
   if(!Inp_UseOB) return 0;
   MqlRates r[]; ArraySetAsSeries(r,true);
   int n=(int)CopyRates(s,InpSignalTF,0,100,r); if(n<30) return 0;
   int cnt=0;
   for(int i=10;i<n-10&&(start+cnt)<max_poi;i++){
      if(i>Inp_MaxAgeBars) continue;
      double body=MathAbs(r[i].close-r[i].open), range=r[i].high-r[i].low;
      if(r[i].close>r[i].open){
         double wick=r[i].open-r[i].low;
         if(wick>body*1.5&&wick>range*0.6){
            bool ok=true;
            for(int j=1;j<=3&&(i-j)>=0;j++) if(r[i-j].close<r[i].low){ ok=false; break; }
            if(ok){
               POI_Info &p=arr[start+cnt++];
               p.price=r[i].low+wick*0.5; p.high=r[i].open; p.low=r[i].low;
               p.dir=BiasBull; p.type=POI_OB; p.time=r[i].time; p.bar=i;
               p.strength=80; p.valid=p.active=true; p.desc="Bull OB";
            }
         }
      }
      if((start+cnt)<max_poi&&r[i].close<r[i].open){
         double wick=r[i].high-r[i].open;
         if(wick>body*1.5&&wick>range*0.6){
            bool ok=true;
            for(int j=1;j<=3&&(i-j)>=0;j++) if(r[i-j].close>r[i].high){ ok=false; break; }
            if(ok){
               POI_Info &p=arr[start+cnt++];
               p.price=r[i].high-wick*0.5; p.high=r[i].high; p.low=r[i].open;
               p.dir=BiasBear; p.type=POI_OB; p.time=r[i].time; p.bar=i;
               p.strength=80; p.valid=p.active=true; p.desc="Bear OB";
            }
         }
      }
   }
   return cnt;
}
bool ValidateEntry(const string s,const POI_Info &p,int idx){
   if(!p.valid||!p.active) return false;
   if(Inp_ReqBias && g_sym[idx].htf!=p.dir && g_sym[idx].htf!=BiasNone) return false;
   double cur=(SymbolInfoDouble(s,SYMBOL_BID)+SymbolInfoDouble(s,SYMBOL_ASK))/2.0;
   double dist=P2R(s,MathAbs(cur-p.price));
   if(dist>Inp_EntryDist) return false;
   bool inZone=false;
   if(p.dir==BiasBull) inZone=(cur>=p.low-P2P(s,5.0)&&cur<=p.high+P2P(s,5.0));
   else                inZone=(cur>=p.low-P2P(s,5.0)&&cur<=p.high+P2P(s,5.0));
   if(!inZone) return false;
   string asset=AssetType(s);
   double maxSp=Inp_MaxSpread;
   if(asset=="METALS") maxSp*=3; else if(asset=="INDICES") maxSp*=5; else if(asset=="CRYPTO") maxSp*=3;
   if(Spread(s)>maxSp) return false;
   MqlRates lr[]; ArraySetAsSeries(lr,true); int c=(int)CopyRates(s,PERIOD_M5,0,5,lr);
   if(c>=3){
      bool rej=false;
      if(p.dir==BiasBull){
         for(int i=0;i<3;i++){ double wick=lr[i].close-lr[i].low,body=MathAbs(lr[i].close-lr[i].open); if(wick>body*2&&lr[i].close>lr[i].open){ rej=true; break; } }
      }else{
         for(int i=0;i<3;i++){ double wick=lr[i].high-lr[i].close,body=MathAbs(lr[i].close-lr[i].open); if(wick>body*2&&lr[i].close<lr[i].open){ rej=true; break; } }
      }
      if(!rej) return false;
   }
   return true;
}

//--------------------------- TP / SL ---------------------------------
TPSLLevels CalcTPSL(const string s,const POI_Info &p,double lots){
   TPSLLevels lvl; ZeroMemory(lvl);
   string asset=AssetType(s);
   double mult=1.0; if(asset=="METALS") mult=1.5; else if(asset=="INDICES") mult=3.0; else if(asset=="CRYPTO") mult=2.0;
   double sl_pips=Inp_SLpips*mult, sl_dist=P2P(s,sl_pips);
   if(p.dir==BiasBull){
      lvl.entry=SymbolInfoDouble(s,SYMBOL_ASK);
      lvl.sl=p.low-P2P(s,2.0);
      if(P2R(s,lvl.entry-lvl.sl)>sl_pips) lvl.sl=lvl.entry-sl_dist;
   }else{
      lvl.entry=SymbolInfoDouble(s,SYMBOL_BID);
      lvl.sl=p.high+P2P(s,2.0);
      if(P2R(s,lvl.sl-lvl.entry)>sl_pips) lvl.sl=lvl.entry+sl_dist;
   }
   lvl.risk=P2R(s,MathAbs(lvl.entry-lvl.sl));
   double minSl=Inp_MinSLpips*mult;
   if(lvl.risk<minSl){
      double minSlPrice=P2P(s,minSl);
      if(p.dir==BiasBull) lvl.sl=lvl.entry-minSlPrice; else lvl.sl=lvl.entry+minSlPrice;
      lvl.risk=minSl;
   }
   lvl.reward=lvl.risk*Inp_TP1RR;
   double tp1_dist=P2P(s,lvl.reward);
   double tp2_reward=lvl.risk*Inp_TP2RR;
   double tp2_dist=P2P(s,tp2_reward);
   if(p.dir==BiasBull){ lvl.tp1=lvl.entry+tp1_dist; lvl.tp2=lvl.entry+tp2_dist; }
   else               { lvl.tp1=lvl.entry-tp1_dist; lvl.tp2=lvl.entry-tp2_dist; }
   lvl.lots=lots; lvl.valid=true;
   return lvl;
}
double CalcLot(const string s,double risk_pips){
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money=balance*(Inp_RiskPct/100.0);
   double tick_size=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0||tick_value<=0) return 0.0;
   double sl_points=risk_pips*PipVal(s)/tick_size;
   double lots=risk_money/(sl_points*tick_value);
   double step=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP);
   double minv=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   lots=MathFloor(lots/step)*step;
   return MathMax(minv,MathMin(lots,maxv));
}

//--------------------------- COUNTS ----------------------------------
int CountPos(const string s){
   int cnt=0;
   for(int i=0;i<PositionsTotal();i++){
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&IsMagic((ulong)PositionGetInteger(POSITION_MAGIC))) cnt++;
   }
   return cnt;
}
int CountPen(const string s){
   int cnt=0;
   for(int i=0;i<OrdersTotal();i++){
      ulong t=OrderGetTicket(i);
      if(OrderSelect(t)&&OrderGetString(ORDER_SYMBOL)==s&&IsMagic((ulong)OrderGetInteger(ORDER_MAGIC))) cnt++;
   }
   return cnt;
}

//--------------------------- PYRAMID ---------------------------------
void InitPyr(int idx,double entry,double sl,BiasDir dir,double lots){
   if(!Inp_PyrOn||idx<0||idx>=g_cnt) return;
   SymbolData &sym=g_sym[idx];
   sym.pyr_on=true; sym.pyr_dir=dir; sym.pyr_entry=entry; sym.pyr_sl=sl;
   sym.pyr_lvl=0; sym.pyr_lots=lots; sym.last_entry=TimeCurrent();
   int maxL=MathMin(Inp_PyrMaxLvl,5);
   for(int i=0;i<maxL;i++){
      PyrLvl &pl=sym.pyr[i];
      pl.lvl=i+1; pl.rr=(i+1)*Inp_PyrAddRR; pl.mult=Inp_PyrMult;
      pl.fill=false; pl.ticket=0;
      double risk=MathAbs(entry-sl);
      double addDist=risk*pl.rr;
      pl.entry=(dir==BiasBull?entry+addDist:entry-addDist);
   }
   Print("✅ PYRAMID INIT: "+sym.sym+" | "+BiasStr(dir));
}
bool ShouldAddPyr(int idx,int &level){
   if(!Inp_PyrOn||idx<0||idx>=g_cnt) return false;
   SymbolData &sym=g_sym[idx];
   if(!sym.pyr_on) return false;
   double cur=(sym.pyr_dir==BiasBull?SymbolInfoDouble(sym.sym,SYMBOL_BID):SymbolInfoDouble(sym.sym,SYMBOL_ASK));
   int maxL=MathMin(Inp_PyrMaxLvl,5);
   for(int i=0;i<maxL;i++){
      if(sym.pyr[i].fill) continue;
      bool reached=(sym.pyr_dir==BiasBull?cur>=sym.pyr[i].entry:cur<=sym.pyr[i].entry);
      if(reached){ level=i; return true; }
   }
   return false;
}
bool AddPyr(int idx,int level){
   if(idx<0||idx>=g_cnt||level<0||level>=5) return false;
   SymbolData &sym=g_sym[idx];
   if(sym.pyr[level].fill) return false;
   double baseLots=sym.pyr_lots/(1+sym.pyr_lvl);
   double addLots=baseLots*sym.pyr[level].mult;
   double step=SymbolInfoDouble(sym.sym,SYMBOL_VOLUME_STEP);
   double minv=SymbolInfoDouble(sym.sym,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(sym.sym,SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   addLots=MathMax(minv,MathMin(MathFloor(addLots/step)*step,maxv));
   int digits=(int)SymbolInfoInteger(sym.sym,SYMBOL_DIGITS);
   double sl=NormalizeDouble(sym.pyr_sl,digits);
   double risk=MathAbs(sym.pyr_entry-sl);
   double tpDist=risk*Inp_TP2RR;
   double tp=NormalizeDouble((sym.pyr_dir==BiasBull?sym.pyr_entry+tpDist:sym.pyr_entry-tpDist),digits);
   MqlTradeRequest req; ZeroMemory(req);
   req.action =TRADE_ACTION_DEAL;
   req.magic  =sym.magic;
   req.symbol =sym.sym;
   req.volume =addLots;
   req.deviation=30;
   req.type   =(sym.pyr_dir==BiasBull?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price  =(sym.pyr_dir==BiasBull?SymbolInfoDouble(sym.sym,SYMBOL_ASK):SymbolInfoDouble(sym.sym,SYMBOL_BID));
   req.sl=sl; req.tp=tp;
   req.type_filling=ORDER_FILLING_RETURN;
   req.comment="PYRAMID_L"+IntegerToString(level+1);
   MqlTradeResult res; if(OrderSend(req,res)&&(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)){
      sym.pyr[level].fill=true;
      sym.pyr[level].ticket=res.order;
      sym.pyr_lvl++; sym.pyr_lots+=addLots;
      PrintFormat("✅ PYRAMID L%d: %s | Lots: %.2f",level+1,sym.sym,addLots);
      LogEvent("PyramidAdded",sym.sym,"Level "+IntegerToString(level+1)+" | Lots: "+DoubleToString(addLots,2));
      if(Inp_PyrMoveSL&&level==0){
         double be=NormalizeDouble(sym.pyr_entry,digits);
         for(int i=0;i<PositionsTotal();i++){
            ulong t=PositionGetTicket(i);
            if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==sym.sym&&(ulong)PositionGetInteger(POSITION_MAGIC)==sym.magic)
               Trade.PositionModify(sym.sym,be,0.0);
         }
      }
      return true;
   }
   return false;
}
void ResetPyr(int idx){
   if(idx<0||idx>=g_cnt) return;
   SymbolData &s=g_sym[idx];
   s.pyr_on=false; s.pyr_lvl=0; s.pyr_lots=0;
   for(int i=0;i<5;i++) s.pyr[i].fill=false;
}
void ManagePyrs(){
   if(!Inp_PyrOn) return;
   for(int i=0;i<g_cnt;i++){
      if(!g_sym[i].pyr_on) continue;
      if(CountPos(g_sym[i].sym)==0){ ResetPyr(i); continue; }
      int lvl; if(ShouldAddPyr(i,lvl)) AddPyr(i,lvl);
   }
}

//--------------------------- TRADE -----------------------------------
void ManagePos(){
   for(int i=0;i<PositionsTotal();i++){
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      if(!IsMagic((ulong)PositionGetInteger(POSITION_MAGIC))) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double cur=(type==POSITION_TYPE_BUY?SymbolInfoDouble(sym,SYMBOL_BID):SymbolInfoDouble(sym,SYMBOL_ASK));
      double risk=MathAbs(entry-curSL);
      double rr=0; if(risk>0) rr=(type==POSITION_TYPE_BUY?(cur-entry)/risk:(entry-cur)/risk);
      if(rr>=Inp_BreakEvenRR){
         double newSL=entry;
         if((type==POSITION_TYPE_BUY&&curSL<newSL)||(type==POSITION_TYPE_SELL&&curSL>newSL))
            Trade.PositionModify(sym,newSL,0.0);
      }
      if(Inp_TrailOn&&rr>=Inp_TrailStartRR){
         double step=P2P(sym,Inp_TrailStep);
         double newSL=(type==POSITION_TYPE_BUY?cur-step:cur+step);
         if((type==POSITION_TYPE_BUY&&newSL>curSL)||(type==POSITION_TYPE_SELL&&newSL<curSL))
            Trade.PositionModify(sym,newSL,0.0);
      }
   }
}

//--------------------------- ORDER -----------------------------------
bool PlaceOrder(const string s,ulong magic,const TPSLLevels &lvl,BiasDir dir){
   if(CountPos(s)+CountPen(s)>=Inp_MaxPos) return false;
   int idx=-1; for(int i=0;i<g_cnt;i++) if(g_sym[i].sym==s){ idx=i; break; }
   if(idx>=0 && TimeCurrent()-g_sym[idx].last_entry<120) return false;
   if(!SymbolSelect(s,true)) return false;
   int digits=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   double entry=NormalizeDouble(lvl.entry,digits);
   double sl   =NormalizeDouble(lvl.sl,digits);
   double tp   =NormalizeDouble(lvl.tp2,digits);
   double lots =lvl.lots;
   MqlTradeRequest req; ZeroMemory(req);
   req.action =TRADE_ACTION_DEAL;
   req.magic  =magic;
   req.symbol =s;
   req.volume =lots;
   req.deviation=30;
   req.type   =(dir==BiasBull?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   req.price  =entry;
   req.sl=sl; req.tp=tp;
   req.type_filling=ORDER_FILLING_RETURN;
   req.comment="SMC_"+s+"_"+DoubleToString(Inp_TP1RR,1)+"R";
   MqlTradeResult res; if(!OrderSend(req,res)) return false;
   if(res.retcode!=TRADE_RETCODE_DONE&&res.retcode!=TRADE_RETCODE_PLACED) return false;
   if(idx>=0){
      g_sym[idx].last_entry=TimeCurrent();
      if(Inp_PyrOn) InitPyr(idx,entry,sl,dir,lots);
   }
   PrintFormat("🎯 SMC ENTRY: %s %s | %.2f lots | Entry=%.5f SL=%.5f TP=%.5f",s,BiasStr(dir),lots,entry,sl,tp);
   LogEvent("OrderPlaced",s,BiasStr(dir)+" Entry="+DoubleToString(entry,5)+" SL="+DoubleToString(sl,5)+" TP="+DoubleToString(tp,5));
   return true;
}

//--------------------------- SYMBOL ----------------------------------
string ResolveSym(const string base){
   if(SymbolSelect(base,true)&&SymbolInfoDouble(base,SYMBOL_BID)>0) return base;
   if(Inp_SuffixAuto){
      int start=0;
      while(true){
         int pos=StringFind(Inp_SuffixCand,";",start);
         string suffix=StringSubstr(Inp_SuffixCand,start,pos-start);
         StringTrimLeft(suffix); StringTrimRight(suffix);
         if(suffix!=""){
            string cand=base+suffix;
            if(SymbolSelect(cand,true)&&SymbolInfoDouble(cand,SYMBOL_BID)>0) return cand;
         }
         if(pos==-1) break;
         start=pos+1;
      }
   }
   return "";
}
void InitSymbols(){
   Print("╔════════════════════════════════════════════════════════╗");
   Print("║  CK SNIPER SMC SCANNER v2.30 – BUILD-5430 PATCHED     ║");
   Print("║  M5-compliant – (c) singhtofc-cell 2025               ║");
   Print("╚════════════════════════════════════════════════════════╝");
   g_cnt=0; int start=0;
   while(start<StringLen(Inp_SymbolList)&&g_cnt<32){
      int pos=StringFind(Inp_SymbolList,";",start);
      string token=StringSubstr(Inp_SymbolList,start,pos-start);
      StringTrimLeft(token); StringTrimRight(token);
      if(StringLen(token)>0){
         string res=ResolveSym(token);
         if(res!=""){
            SymbolData &sym=g_sym[g_cnt++];
            sym.name=token; sym.sym=res; sym.magic=(ulong)Inp_Magic+(ulong)g_cnt;
            sym.tradable=true; sym.asset=AssetType(res);
            sym.htf=BiasNone; sym.ltf=BiasNone; sym.poi_cnt=0; sym.last_entry=0; sym.pyr_on=false;
            sym.win=sym.loss=sym.trades=0;
            Print("✅ ["+IntegerToString(g_cnt)+"] "+token+" ("+res+") ["+sym.asset+"]");
         }
      }
      if(pos==-1) break;
      start=pos+1;
   }
   Print("════════════════════════════════════════════════════════");
   Print("✅ Loaded "+IntegerToString(g_cnt)+"/32 symbols – M5 ready");
   Print("════════════════════════════════════════════════════════");
}

//--------------------------- SCAN ------------------------------------
void ScanAndTrade(){
   datetime now=TimeCurrent(); if(now-g_last_scan<60) return; g_last_scan=now;
   for(int i=0;i<g_cnt;i++){
      SymbolData &sym=g_sym[i]; if(!sym.tradable) continue;
      string s=sym.sym;
      sym.htf=HTFbias(s); sym.ltf=LTFbias(s);
      int fvg=DetectFVG(s,sym.poi,10);
      int ob =DetectOB(s,sym.poi,fvg,10);
      sym.poi_cnt=fvg+ob;
      for(int p=0;p<sym.poi_cnt;p++){
         if(!ValidateEntry(s,sym.poi[p],i)) continue;
         double lots=CalcLot(s,Inp_SLpips);
         TPSLLevels lvl=CalcTPSL(s,sym.poi[p],lots);
         if(!lvl.valid) continue;
         if(PlaceOrder(s,sym.magic,lvl,sym.poi[p].dir)){
            sym.poi[p].active=false; break;
         }
      }
   }
}

//--------------------------- DASHBOARD -------------------------------
string g_dash_obj[500]; int g_dash_cnt=0;
void DashDelete(){
   for(int i=0;i<g_dash_cnt;i++) ObjectDelete(0,g_dash_obj[i]);
   g_dash_cnt=0; ChartRedraw();
}
void DashLabel(const string name,int x,int y,string txt,int size,color clr,int w=0,int h=0){
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(w>0&&h>0){
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clr); ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   }else{
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER); ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas"); ObjectSetString(0,name,OBJPROP_TEXT,txt);
   }
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_BACK,false);
   if(g_dash_cnt<500) g_dash_obj[g_dash_cnt++]=name;
}
void DashCreate(){
   if(!Inp_DashOn) return;
   int x=Inp_DashX, y=Inp_DashY;
   DashLabel("CK_BG",x,y,"",Inp_FontSize,Inp_DashBG,1000,650);
   DashLabel("CK_HDR",x+15,y+10,"",Inp_FontSize+2,clrYellow);
   DashLabel("CK_BAL_L",x+15,y+40,"Balance:",Inp_FontSize,Inp_DashTxt);
   DashLabel("CK_BAL_V",x+90,y+40,"",Inp_FontSize,clrAqua);
   DashLabel("CK_SESS_L",x+220,y+40,"Session:",Inp_FontSize,Inp_DashTxt);
   DashLabel("CK_SESS_V",x+290,y+40,"",Inp_FontSize,clrLime);
   DashLabel("CK_TIME_L",x+420,y+40,"UTC:",Inp_FontSize,Inp_DashTxt);
   DashLabel("CK_TIME_V",x+470,y+40,"",Inp_FontSize,clrWhite);
   DashLabel("CK_PYR_L",x+600,y+40,"Pyramid:",Inp_FontSize,Inp_DashTxt);
   DashLabel("CK_PYR_V",x+670,y+40,"",Inp_FontSize,clrOrange);
   int rowY=y+65;
   DashLabel("CK_LINE1",x+15,rowY,"──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────",Inp_FontSize-1,clrGray);
   rowY+=18;
   string hdr[9]={"SYMBOL","TYPE","HTF","LTF","POIs","POS","PYR","P&L","WIN%"};
   int dx[9]={15,90,150,230,290,340,390,440,520};
   for(int i=0;i<9;i++) DashLabel("CK_H"+IntegerToString(i),x+dx[i],rowY,hdr[i],Inp_FontSize,clrWhite);
   rowY+=18;
   DashLabel("CK_LINE2",x+15,rowY,"──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────",Inp_FontSize-1,clrGray);
   rowY+=18;
   for(int i=0;i<20;i++){
      string pre="CK_R"+IntegerToString(i);
      for(int j=0;j<9;j++) DashLabel(pre+"_C"+IntegerToString(j),x+dx[j],rowY,"",Inp_FontSize-1,clrGray);
      rowY+=20;
   }
   ChartRedraw();
}
void DashUpdate(){
   if(!Inp_DashOn) return;
   ObjectSetString(0,"CK_HDR",OBJPROP_TEXT,StringFormat("🎯 CK SNIPER SMC v2.30 – BUILD-5430 PATCHED | M5 | %d/32 | %s",g_cnt,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)));
   ObjectSetString(0,"CK_BAL_V",OBJPROP_TEXT,"$"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int h=dt.hour,dow=dt.day_of_week;
   string sess="🔴 CLOSED"; color sessClr=clrRed;
   if(dow!=0 && dow!=6){
      if((h>=21||h<6)||(h>=0&&h<9)||(h>=8&&h<17)||(h>=13&&h<22)){ sess="🟢 "; sessClr=clrLime;
         if(h>=21||h<6) sess+="SYD"; if(h>=0&&h<9) sess+="+TKY";
         if(h>=8&&h<17) sess+="+LON"; if(h>=13&&h<22) sess+="+NYC";
      }
   }
   ObjectSetString(0,"CK_SESS_V",OBJPROP_TEXT,sess); ObjectSetInteger(0,"CK_SESS_V",OBJPROP_COLOR,sessClr);
   ObjectSetString(0,"CK_TIME_V",OBJPROP_TEXT,TimeToString(TimeCurrent(),TIME_SECONDS));
   int pAct=0; for(int i=0;i<g_cnt;i++) if(g_sym[i].pyr_on) pAct++;
   string pTxt=Inp_PyrOn?(pAct>0?"🟢 "+IntegerToString(pAct)+" ACTIVE":"🟡 READY"):"🔴 OFF";
   color pClr=Inp_PyrOn?(pAct>0?clrLime:clrOrange):clrRed;
   ObjectSetString(0,"CK_PYR_V",OBJPROP_TEXT,pTxt); ObjectSetInteger(0,"CK_PYR_V",OBJPROP_COLOR,pClr);
   for(int i=0;i<20;i++){
      string pre="CK_R"+IntegerToString(i);
      if(i<g_cnt){
         SymbolData &sym=g_sym[i];
         ObjectSetString(0,pre+"_C0",OBJPROP_TEXT,sym.name);
         ObjectSetString(0,pre+"_C1",OBJPROP_TEXT,sym.asset);
         string htf=BiasStr(sym.htf); color htfClr=clrGray;
         if(sym.htf==BiasBull){ htf="🔺 "+htf; htfClr=Inp_DashGain; } else if(sym.htf==BiasBear){ htf="🔻 "+htf; htfClr=Inp_DashLoss; }
         ObjectSetString(0,pre+"_C2",OBJPROP_TEXT,htf); ObjectSetInteger(0,pre+"_C2",OBJPROP_COLOR,htfClr);
         string ltf=(sym.ltf==BiasBull?"↑":sym.ltf==BiasBear?"↓":"─");
         color ltfClr=(sym.ltf==BiasBull?clrLime:sym.ltf==BiasBear?clrRed:clrGray);
         ObjectSetString(0,pre+"_C3",OBJPROP_TEXT,ltf); ObjectSetInteger(0,pre+"_C3",OBJPROP_COLOR,ltfClr);
         ObjectSetString(0,pre+"_C4",OBJPROP_TEXT,IntegerToString(sym.poi_cnt));
         ObjectSetInteger(0,pre+"_C4",OBJPROP_COLOR,sym.poi_cnt>0?clrYellow:clrGray);
         ObjectSetString(0,pre+"_C5",OBJPROP_TEXT,IntegerToString(sym.pos_cnt));
         ObjectSetInteger(0,pre+"_C5",OBJPROP_COLOR,sym.pos_cnt>0?clrAqua:clrGray);
         string pyr="-"; color pClr=clrGray;
         if(sym.pyr_on){ pyr="L"+IntegerToString(sym.pyr_lvl)+"/"+IntegerToString(Inp_PyrMaxLvl); pClr=clrOrange; }
         ObjectSetString(0,pre+"_C6",OBJPROP_TEXT,pyr); ObjectSetInteger(0,pre+"_C6",OBJPROP_COLOR,pClr);
         string pl=(sym.run_pl>=0?"+":"")+DoubleToString(sym.run_pl,2);
         ObjectSetString(0,pre+"_C7",OBJPROP_TEXT,pl); ObjectSetInteger(0,pre+"_C7",OBJPROP_COLOR,sym.run_pl>=0?Inp_DashGain:Inp_DashLoss);
         ObjectSetString(0,pre+"_C8",OBJPROP_TEXT,(sym.trades>0?DoubleToString((double)sym.win/sym.trades*100,0)+"%":"-"));
         ObjectSetInteger(0,pre+"_C8",OBJPROP_COLOR,sym.trades>0?(sym.win>=sym.loss?Inp_DashGain:Inp_DashLoss):clrGray);
      }else{
         for(int j=0;j<9;j++) ObjectSetString(0,pre+"_C"+IntegerToString(j),OBJPROP_TEXT,"");
      }
   }
   ChartRedraw();
}

//--------------------------- EVENTS ----------------------------------
int OnInit(){
   InitSymbols();
   if(Inp_LogCSV) LogEvent("EA_START","SYSTEM","Build-5430 patched – M5 default");
   DashCreate(); DashUpdate();
   EventSetTimer(5);
   Print("✅ CK SNIPER SMC v2.30 – BUILD-5430 PATCHED – 0 ERRORS");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){
   DashDelete();
   string r=""; switch(reason){
      case REASON_PROGRAM: r="User stopped"; break;
      case REASON_REMOVE: r="Removed"; break;
      case REASON_RECOMPILE: r="Recompiled"; break;
      case REASON_CHARTCLOSE: r="Chart closed"; break;
      case REASON_PARAMETERS: r="Params changed"; break;
      default: r="Other";
   }
   LogEvent("EA_STOP","SYSTEM",r);
   Print("🛑 CK Sniper SMC v2.30 stopped: "+r);
}
void OnTick(){
   datetime now=TimeCurrent(); if(now-g_last_up<5) return; g_last_up=now;
   if(Inp_EnTrading){ ScanAndTrade(); ManagePos(); ManagePyrs(); }
   for(int i=0;i<g_cnt;i++){
      SymbolData &sym=g_sym[i];
      sym.pos_cnt=CountPos(sym.sym);
      sym.pen_cnt=CountPen(sym.sym);
      sym.run_pl=0;
      for(int j=0;j<PositionsTotal();j++){
         ulong t=PositionGetTicket(j);
         if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==sym.sym&&IsMagic((ulong)PositionGetInteger(POSITION_MAGIC)))
            sym.run_pl+=PositionGetDouble(POSITION_PROFIT);
      }
      MqlDateTime day; TimeToStruct(TimeCurrent(),day); day.hour=day.min=day.sec=0;
      datetime start=StructToTime(day);
      if(HistorySelect(start,TimeCurrent())){
         sym.win=sym.loss=sym.trades=0;
         for(int j=0;j<(int)HistoryDealsTotal();j++){
            ulong t=HistoryDealGetTicket(j); if(t==0) continue;
            if(HistoryDealGetString(t,DEAL_SYMBOL)!=sym.sym) continue;
            if(!IsMagic((ulong)HistoryDealGetInteger(t,DEAL_MAGIC))) continue;
            if(HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
            double pnl=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION);
            sym.trades++; if(pnl>0) sym.win++; else sym.loss++;
         }
      }
   }
   DashUpdate();
}
void OnTimer(){ DashUpdate(); }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result){
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD){
      ulong deal=trans.deal; if(deal==0) return;
      if(!IsMagic((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC))) return;
      string sym=HistoryDealGetString(deal,DEAL_SYMBOL);
      int entry=(int)HistoryDealGetInteger(deal,DEAL_ENTRY);
      double price=HistoryDealGetDouble(deal,DEAL_PRICE);
      double profit=HistoryDealGetDouble(deal,DEAL_PROFIT);
      if(entry==DEAL_ENTRY_IN)  LogEvent("POS_OPEN",sym,"Opened at "+DoubleToString(price,5));
      if(entry==DEAL_ENTRY_OUT) LogEvent("POS_CLOSE",sym,"Closed at "+DoubleToString(price,5)+" | P&L: $"+DoubleToString(profit,2));
      DashUpdate();
   }
}
//+------------------------------------------------------------------+...
