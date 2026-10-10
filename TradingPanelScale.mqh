//+------------------------------------------------------------------+
//| TradingPanelScale.mqh — makes the panel the same size on every    |
//| screen (Mac Retina, Windows at 125/150/200% scaling).             |
//+------------------------------------------------------------------+
//--- Why: MT5 scales object FONTS by the screen's DPI, but object
//--- POSITIONS and SIZES are raw pixels. On a Mac (MT5 runs in Wine at
//--- Retina resolution, DPI 192 — measured with tools/PanelDiagnostics.mq5)
//--- text came out 2x while every box stayed 1x, so labels overflowed and
//--- numbers were clipped.
//---
//--- How: the whole panel — our code AND MetaQuotes' Controls library —
//--- keeps working in "panel pixels" (Windows at 100%). The three functions
//--- below are the only places pixels meet the chart: they convert panel
//--- pixels to screen pixels on the way in and back on the way out, for the
//--- pixel properties only (positions/sizes). Fonts are left to MT5, which
//--- already scales them. Mouse coordinates are converted the same way in
//--- OnChartEvent (TradingPanel.mq5) before the dialog sees them.
//---
//--- The #defines at the bottom route every ObjectSetInteger/
//--- ObjectGetInteger/ChartGetInteger call that comes after this file —
//--- including the ones inside <Controls\...> — through these wrappers, so
//--- this file MUST be included before any <Controls\...> include. At DPI 96
//--- the scale is exactly 1 and every wrapper is a pass-through, so Windows
//--- at 100% behaves exactly as before.
#ifndef TRADINGPANEL_SCALE_MQH
#define TRADINGPANEL_SCALE_MQH

//--- Screen pixels per panel pixel (DPI / 96). Never below 1: a low-DPI
//--- screen keeps the panel at its designed size rather than shrinking it.
double UiScale()
{
   static double scale = 0.0;
   if(scale <= 0.0)
   {
      int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
      scale = (dpi > 96) ? dpi / 96.0 : 1.0;
   }
   return scale;
}

long UiToScreen(const long panelPx)   { return (long)MathRound(panelPx * UiScale()); }
long UiFromScreen(const long screenPx) { return (long)MathRound(screenPx / UiScale()); }

bool UiIsPixelProp(const ENUM_OBJECT_PROPERTY_INTEGER prop)
{
   return prop == OBJPROP_XDISTANCE || prop == OBJPROP_YDISTANCE ||
          prop == OBJPROP_XSIZE     || prop == OBJPROP_YSIZE     ||
          prop == OBJPROP_XOFFSET   || prop == OBJPROP_YOFFSET;
}

bool UiIsChartPixelProp(const ENUM_CHART_PROPERTY_INTEGER prop)
{
   return prop == CHART_WIDTH_IN_PIXELS || prop == CHART_HEIGHT_IN_PIXELS || prop == CHART_WINDOW_YDISTANCE;
}

//--- Same overloads as the built-ins they stand in for.
bool UiObjectSetInteger(long chart_id, string name, ENUM_OBJECT_PROPERTY_INTEGER prop, long value)
{
   return ObjectSetInteger(chart_id, name, prop, UiIsPixelProp(prop) ? UiToScreen(value) : value);
}
bool UiObjectSetInteger(long chart_id, string name, ENUM_OBJECT_PROPERTY_INTEGER prop, int modifier, long value)
{
   return ObjectSetInteger(chart_id, name, prop, modifier, UiIsPixelProp(prop) ? UiToScreen(value) : value);
}
long UiObjectGetInteger(long chart_id, string name, ENUM_OBJECT_PROPERTY_INTEGER prop, int modifier = 0)
{
   long value = ObjectGetInteger(chart_id, name, prop, modifier);
   return UiIsPixelProp(prop) ? UiFromScreen(value) : value;
}
bool UiObjectGetInteger(long chart_id, string name, ENUM_OBJECT_PROPERTY_INTEGER prop, int modifier, long &value)
{
   if(!ObjectGetInteger(chart_id, name, prop, modifier, value)) return false;
   if(UiIsPixelProp(prop)) value = UiFromScreen(value);
   return true;
}
long UiChartGetInteger(long chart_id, ENUM_CHART_PROPERTY_INTEGER prop, int sub_window = 0)
{
   long value = ChartGetInteger(chart_id, prop, sub_window);
   return UiIsChartPixelProp(prop) ? UiFromScreen(value) : value;
}
bool UiChartGetInteger(long chart_id, ENUM_CHART_PROPERTY_INTEGER prop, int sub_window, long &value)
{
   if(!ChartGetInteger(chart_id, prop, sub_window, value)) return false;
   if(UiIsChartPixelProp(prop)) value = UiFromScreen(value);
   return true;
}

#define ObjectSetInteger UiObjectSetInteger
#define ObjectGetInteger UiObjectGetInteger
#define ChartGetInteger  UiChartGetInteger

#endif // TRADINGPANEL_SCALE_MQH
