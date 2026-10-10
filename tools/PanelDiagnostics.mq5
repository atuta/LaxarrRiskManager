//+------------------------------------------------------------------+
//| PanelDiagnostics.mq5 — run once on Windows and once on Mac, then  |
//| compare the Experts log and a screenshot of the sample boxes.      |
//| Finds out WHY the trading panel renders differently on Mac/Wine:   |
//| screen DPI, missing fonts, or text drawn wider than on Windows.    |
//| Draws a few sample controls (removed when the script ends, after   |
//| 60 seconds) and changes nothing else.                              |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input int ShowSamplesSeconds = 60; // How long to leave the sample boxes on the chart

#define PFX "PanelDiag_"

void Measure(const string font, const int points)
{
   uint w = 0, h = 0, w2 = 0, h2 = 0;
   //--- Negative size = tenths of a point, scaled by the OS like the
   //--- panel's own 9pt object fonts. Positive size = fixed, not scaled.
   //--- If the two differ a lot on Mac but not on Windows, DPI is the cause.
   if(!TextSetFont(font, -points * 10))
   {
      PrintFormat("  %-14s -> font NOT available (error %d)", font, GetLastError());
      return;
   }
   TextGetSize("Volume: 0.59410", w, h);
   TextSetFont(font, 12);
   TextGetSize("Volume: 0.59410", w2, h2);
   PrintFormat("  %-14s 'Volume: 0.59410' -> %3u x %2u px at %dpt (OS-scaled), %3u x %2u px unscaled",
               font, w, h, points, w2, h2);
}

void Sample(const string name, const ENUM_OBJECT type, const int x, const int y, const int w, const int h,
            const string text, const string font)
{
   ObjectCreate(0, PFX + name, type, 0, 0, 0);
   ObjectSetInteger(0, PFX + name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PFX + name, OBJPROP_YDISTANCE, y);
   if(type != OBJ_LABEL)
   {
      ObjectSetInteger(0, PFX + name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, PFX + name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, PFX + name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, PFX + name, OBJPROP_BORDER_COLOR, clrRed);
   }
   ObjectSetString(0, PFX + name, OBJPROP_TEXT, text);
   ObjectSetString(0, PFX + name, OBJPROP_FONT, font);
   ObjectSetInteger(0, PFX + name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, PFX + name, OBJPROP_COLOR, clrBlack);
}

void OnStart()
{
   Print("===== Trading panel diagnostics =====");
   PrintFormat("Terminal build %d, %s", TerminalInfoInteger(TERMINAL_BUILD), TerminalInfoString(TERMINAL_NAME));
   PrintFormat("Terminal path: %s", TerminalInfoString(TERMINAL_PATH)); // a Wine install shows drive_c / a Mac path
   PrintFormat("Screen DPI: %d (Windows at 100%% scaling = 96)", TerminalInfoInteger(TERMINAL_SCREEN_DPI));
   PrintFormat("Chart size: %d x %d px",
               ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS));
   Print("Text width of the same string in each font (the panel uses 9pt):");
   Measure("Arial", 9);
   Measure("Tahoma", 9);
   Measure("Segoe UI", 9);
   Measure("Trebuchet MS", 9);
   Measure("Calibri", 9);
   Measure("Courier New", 9);

   //--- The panel's real controls are fixed-pixel boxes with 9pt text.
   //--- Each red box below is 130 x 22 px: on Windows the text fits with
   //--- room to spare. Screenshot these on both machines.
   Sample("Lbl",  OBJ_LABEL, 20, 40,   0,  0, "Label Arial 9pt: Volume 0.59410", "Arial");
   Sample("Edt1", OBJ_EDIT,  20, 70, 130, 22, "0.59410 Arial",      "Arial");
   Sample("Edt2", OBJ_EDIT,  20, 100, 130, 22, "0.59410 Tahoma",    "Tahoma");
   Sample("Btn",  OBJ_BUTTON, 20, 130, 130, 22, "Execute Arial",     "Arial");
   ChartRedraw();
   Print("Sample boxes drawn top-left — screenshot them now. They disappear in ", ShowSamplesSeconds, "s.");

   Sleep(ShowSamplesSeconds * 1000);
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
   Print("===== end of diagnostics =====");
}
