// ============================================================
// main.cpp - Karachi Route Finder GUI (Win32 + GDI)
//
// C++ only opens the window and draws. ALL the data, string and
// file logic is written in x86 assembly (DijkstraCore.asm):
//   * the road graph and Dijkstra's algorithm
//   * area names, searching a typed name, clicking a place
//   * the favourite places  (favourites.txt)
//   * the route history     (route_history.txt)
//   * building the route and the history line (text formatting)
//
//  Background : real OpenStreetMap picture of Karachi (karachi_map.bmp)
//  Map data   : MapData.h (junction positions, roads, road shapes, areas)
//
// Build as x86 (Win32). Put karachi_map.bmp in the project folder.
// ============================================================
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <commdlg.h>
#include "MapData.h"

#pragma comment(linker, "/SUBSYSTEM:WINDOWS")
#pragma comment(linker, "/ENTRY:mainCRTStartup")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "msimg32.lib")
#pragma comment(lib, "comdlg32.lib")

// ---------- procedures written in assembly (DijkstraCore.asm) ----------
extern "C" {
    // graph and Dijkstra
    void GraphReset(int cnt);
    void GraphAddEdge(int u, int v, int w);
    void SetNodePos(int idx, int x, int y);
    void AddLandmark(const char* name, int node);
    void DataInit();
    void DijkstraInit(int srcNode);
    int  DijkstraStep();
    int  GetDist(int idx);
    int  GetPrev(int idx);
    int  GetVisited(int idx);
    // route
    int  BuildPath(int dstNode);
    int  GetPathLen();
    int  GetPathNode(int i);
    void RouteString(char* out);
    // map
    int  NodeSX(int idx);
    int  NodeSY(int idx);
    int  HitLandmark(int sx, int sy, int radius2);
    int  HitNode(int sx, int sy);
    void NodeName(int node, char* out);
    // places (areas + favourites)
    int  PlaceCount();
    const char* PlaceNameAt(int i);
    int  PlaceNodeAt(int i);
    int  FindPlace(const char* text);
    // favourites (favourites.txt)
    int  FavSet(int favIdx, int node, int type, const char* name);
    int  FavDelete(int idx);
    int  FavCount();
    int  FavNodeAt(int i);
    int  FavTypeAt(int i);
    const char* FavNameAt(int i);
    int  FavOfNodeAt(int node);
    // route history (route_history.txt)
    int  HistAppend(int srcNode, int dstNode, int steps);
    int  HistLoad();
    int  ClearHistory();
    int  HistCount();
    int  HistRecentN();
    const char* HistRecentAt(int k);
    const char* GetHistPath();
    int  FavClearAll();
    const char* GetFavPath();
}

// ---------- layout ----------
static const int    MAP_W = 960, MAP_H = 696, WIN_W = 1260, WIN_H = 700;
static const double SCL = 960.0 / 1270.0;            // screenshot pixels -> window pixels
static int NX(int i) { return NodeSX(i); }           // junction position on the screen (assembly)
static int NY(int i) { return NodeSY(i); }

// ---------- state ----------
enum { PICK_START, PICK_STOP, RUNNING, DONE };
static int  state = PICK_START;
static int  src = -1, dst = -1, lastU = -1, steps = 0, speedIdx = 1;
static const int SPT[] = { 1, 2, 3, 5, 8, 12 };      // Dijkstra steps per timer tick
static bool started = false;
static int  pathLen = 0;
static char gMsg[220] = "";
static HWND hMain, hFrom, hTo, hGo, hReset, hHist, hClear, hFavView, hFavClear;
static HWND hFavEdit, hFavSave, hFavStar, hFavDel, hFavCancel;
static HFONT fSmall, fBold, fTitle, fLm;
static HDC  hMapDC = NULL;
static int  mapW = 0, mapH = 0;
static int  hoverLm = -1;                            // area under the mouse
static bool showAll = false;                         // L key: label every area
static int  pendingNode = -1, pendingFav = -1;       // point chosen with the right mouse button
static short edgeOf[NNODES][NNODES];                 // road number between two junctions (for drawing)

#define ID_GO    101
#define ID_RESET 102
#define ID_HIST  103
#define ID_CLEAR 104
#define ID_FSAVE 105
#define ID_FDEL  106
#define ID_FCANCEL 107
#define ID_FSTAR 108
#define ID_FAVVIEW  109
#define ID_FAVCLEAR 110

// ---------- helpers ----------
static void SetMsg(const char* s) { strncpy_s(gMsg, sizeof(gMsg), s, _TRUNCATE); }

// hands the whole map to the assembly module
static void InitMapData()
{
    for (int a = 0; a < NNODES; a++) for (int b = 0; b < NNODES; b++) edgeOf[a][b] = -1;
    for (int e = 0; e < NEDGES; e++) { edgeOf[EDGE_U[e]][EDGE_V[e]] = (short)e; edgeOf[EDGE_V[e]][EDGE_U[e]] = (short)e; }
    GraphReset(NNODES);                                          // assembly
    for (int i = 0; i < NNODES; i++) SetNodePos(i, NODE_X[i], NODE_Y[i]);
    for (int k = 0; k < NLM; k++) AddLandmark(LMS[k].name, LMS[k].node);
    for (int e = 0; e < NEDGES; e++) GraphAddEdge(EDGE_U[e], EDGE_V[e], EDGE_W[e]);
    DataInit();     // file names, area tables, favourites.txt and route_history.txt are read here
}

static bool TryLoadBmp(const char* path)
{
    HBITMAP hb = (HBITMAP)LoadImageA(NULL, path, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE | LR_CREATEDIBSECTION);
    if (!hb) return false;
    BITMAP bm; GetObject(hb, sizeof(bm), &bm);
    mapW = bm.bmWidth; mapH = bm.bmHeight;
    HDC sc = GetDC(NULL);
    hMapDC = CreateCompatibleDC(sc);
    ReleaseDC(NULL, sc);
    SelectObject(hMapDC, hb);
    return true;
}

// looks for karachi_map.bmp in several places, then lets the user browse for it
static void LoadMapBitmap()
{
    char exe[MAX_PATH];
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    char* sl = strrchr(exe, '\\');
    if (sl) *(sl + 1) = 0;                               // program folder, with trailing '\'
    char srcDir[MAX_PATH];
    strcpy_s(srcDir, __FILE__);                          // folder where main.cpp lives
    sl = strrchr(srcDir, '\\');
    if (sl) *(sl + 1) = 0; else srcDir[0] = 0;

    char dirs[6][MAX_PATH];
    strcpy_s(dirs[0], "");                               // current working folder
    strcpy_s(dirs[1], exe);
    sprintf_s(dirs[2], "%s..\\", exe);
    sprintf_s(dirs[3], "%s..\\..\\", exe);
    sprintf_s(dirs[4], "%s..\\..\\..\\", exe);
    strcpy_s(dirs[5], srcDir);
    for (int i = 0; i < 6; i++) {
        char p[MAX_PATH * 2];
        sprintf_s(p, "%skarachi_map.bmp", dirs[i]);
        if (TryLoadBmp(p)) return;
    }

    MessageBoxA(NULL, "karachi_map.bmp was not found next to the program.\nClick OK, then select the file.",
                "Karachi Route Finder", MB_OK | MB_ICONINFORMATION);
    char file[MAX_PATH] = "karachi_map.bmp";
    OPENFILENAMEA ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.lpstrFilter = "Bitmap (*.bmp)\0*.bmp\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = "Select karachi_map.bmp";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (GetOpenFileNameA(&ofn)) TryLoadBmp(file);
}

// ---------- From / To drop-down lists: all areas + all favourites ----------
static void FillPlaceLists()
{
    char a[64], b[64];
    GetWindowTextA(hFrom, a, sizeof(a));
    GetWindowTextA(hTo, b, sizeof(b));
    SendMessageA(hFrom, CB_RESETCONTENT, 0, 0);
    SendMessageA(hTo,   CB_RESETCONTENT, 0, 0);
    for (int i = 0; i < PlaceCount(); i++) {
        SendMessageA(hFrom, CB_ADDSTRING, 0, (LPARAM)PlaceNameAt(i));
        SendMessageA(hTo,   CB_ADDSTRING, 0, (LPARAM)PlaceNameAt(i));
    }
    SetWindowTextA(hFrom, a);
    SetWindowTextA(hTo, b);
}

// ---------- favourite places: name bar (the file work is done in assembly) ----------
static void CloseFavBar()
{
    pendingNode = pendingFav = -1;
    ShowWindow(hFavEdit, SW_HIDE); ShowWindow(hFavSave, SW_HIDE); ShowWindow(hFavStar, SW_HIDE);
    ShowWindow(hFavDel, SW_HIDE);  ShowWindow(hFavCancel, SW_HIDE);
    SetFocus(hMain);
    InvalidateRect(hMain, NULL, FALSE);
}

static void OpenFavBar(int node)
{
    pendingNode = node;
    pendingFav = FavOfNodeAt(node);
    SetWindowTextA(hFavEdit, pendingFav >= 0 ? FavNameAt(pendingFav) : "");
    ShowWindow(hFavEdit, SW_SHOW); ShowWindow(hFavSave, SW_SHOW); ShowWindow(hFavStar, SW_SHOW); ShowWindow(hFavCancel, SW_SHOW);
    ShowWindow(hFavDel, pendingFav >= 0 ? SW_SHOW : SW_HIDE);
    SetFocus(hFavEdit);
    char nm[96], b[260];
    NodeName(node, nm);                                          // assembly
    if (pendingFav >= 0) sprintf_s(b, "\"%s\" selected. Change its name or icon, delete it, or cancel.", nm);
    else                 sprintf_s(b, "Selected: %s. Type a name, then save it as a Heart (home) or a Star (other place).", nm);
    SetMsg(b);
    InvalidateRect(hMain, NULL, FALSE);
}

static void SaveFav(char type)
{
    if (pendingNode < 0) return;
    char t[64];
    GetWindowTextA(hFavEdit, t, sizeof(t));
    int r = FavSet(pendingFav, pendingNode, type, t);            // assembly: cleans + checks the name, writes favourites.txt
    if (r != 0) {
        if (r == 1)      SetMsg("Please type a name first.");
        else if (r == 2) SetMsg("You already have a favourite with that name.");
        else if (r == 3) SetMsg("That name belongs to a built-in area. Pick another name.");
        else             SetMsg("Favourites list is full.");
        InvalidateRect(hMain, NULL, FALSE);
        return;
    }
    int idx = (pendingFav >= 0) ? pendingFav : FavCount() - 1;
    char b[160];
    sprintf_s(b, "Saved \"%s\" to favourites.txt.", FavNameAt(idx));
    FillPlaceLists();
    CloseFavBar();
    SetMsg(b);
    InvalidateRect(hMain, NULL, FALSE);
}

static void DeleteFav()
{
    if (pendingFav < 0) return;
    char b[160];
    sprintf_s(b, "Removed \"%s\" from favourites.", FavNameAt(pendingFav));
    FavDelete(pendingFav);                                       // assembly: shifts the list, rewrites the file
    FillPlaceLists();
    CloseFavBar();
    SetMsg(b);
    InvalidateRect(hMain, NULL, FALSE);
}

// ---------- control of the animation ----------
static void ResetAll()
{
    KillTimer(hMain, 1);
    state = PICK_START; src = dst = lastU = -1; steps = 0;
    started = false; pathLen = 0;
    SetWindowTextA(hFrom, ""); SetWindowTextA(hTo, "");
    SetMsg("Click a place on the map (or type names) to choose the START.");
    InvalidateRect(hMain, NULL, FALSE);
}

static void StartRun(int s, int d)
{
    src = s; dst = d; lastU = -1; steps = 0; pathLen = 0;
    char nm[96];
    NodeName(s, nm); SetWindowTextA(hFrom, nm);
    NodeName(d, nm); SetWindowTextA(hTo, nm);
    DijkstraInit(s);                                             // assembly
    started = true;
    state = RUNNING;
    SetMsg("Searching... the blue tree shows the shortest routes found so far.");
    SetTimer(hMain, 1, 30, NULL);
    InvalidateRect(hMain, NULL, FALSE);
}

static void OneStep()
{
    int u = DijkstraStep();                                      // assembly: one iteration
    steps++;
    if (u < 0) {
        KillTimer(hMain, 1); state = DONE; lastU = -1;
        SetMsg("No route found between these places.");
        return;
    }
    lastU = u;
    if (u == dst) {
        KillTimer(hMain, 1); state = DONE; lastU = -1;
        pathLen = BuildPath(dst);                                // assembly: route from prev[]
        if (HistAppend(src, dst, steps))                         // assembly: builds the line + appends it to the file
            sprintf_s(gMsg, "Done! Saved as record #%d in route_history.txt. Click any place to run again.", HistCount());
        else
            SetMsg("Done! (Could not write route_history.txt)");
    }
}

static void Tick()
{
    for (int k = 0; k < SPT[speedIdx] && state == RUNNING; k++) OneStep();
    InvalidateRect(hMain, NULL, FALSE);
}

static void OnPick(int node)
{
    if (state == RUNNING) return;
    if (state == DONE) ResetAll();
    char nm[96];
    NodeName(node, nm);
    if (state == PICK_START) {
        src = node; state = PICK_STOP;
        SetWindowTextA(hFrom, nm);
        char b[160]; sprintf_s(b, "Start: %s.  Now click the STOP.", nm);
        SetMsg(b);
    } else if (state == PICK_STOP) {
        if (node == src) SetMsg("Stop must be different from the start.");
        else StartRun(src, node);
    }
    InvalidateRect(hMain, NULL, FALSE);
}

static void OnGo()
{
    if (state == RUNNING) return;
    char a[64], b[64];
    GetWindowTextA(hFrom, a, sizeof(a));
    GetWindowTextA(hTo, b, sizeof(b));
    int s, d;
    if (state == PICK_STOP && src >= 0) s = src;                 // start was clicked on the map
    else { int k = FindPlace(a); s = (k >= 0) ? PlaceNodeAt(k) : -1; }   // assembly: search by typed name
    int kd = FindPlace(b);
    d = (kd >= 0) ? PlaceNodeAt(kd) : -1;
    if (s < 0) { SetMsg("Start place not found. Check the spelling."); InvalidateRect(hMain, NULL, FALSE); return; }
    if (d < 0) { SetMsg("Stop place not found. Check the spelling."); InvalidateRect(hMain, NULL, FALSE); return; }
    if (s == d) { SetMsg("Start and stop are the same place."); InvalidateRect(hMain, NULL, FALSE); return; }
    StartRun(s, d);
}

// ---------- drawing ----------
static void DrawEdge(HDC dc, int e)
{
    POINT pts[32];
    int a = EDGE_PS[e], n = EDGE_PS[e + 1] - a;
    if (n > 32) n = 32;
    for (int i = 0; i < n; i++) {
        pts[i].x = (LONG)(POLY_X[a + i] * SCL + 0.5);
        pts[i].y = (LONG)(POLY_Y[a + i] * SCL + 0.5);
    }
    Polyline(dc, pts, n);
}

static void Disc(HDC dc, int x, int y, int r, COLORREF fill, COLORREF edge, int ew)
{
    HPEN p = CreatePen(PS_SOLID, ew, edge);
    HBRUSH br = CreateSolidBrush(fill);
    HGDIOBJ op = SelectObject(dc, p), ob = SelectObject(dc, br);
    Ellipse(dc, x - r, y - r, x + r + 1, y + r + 1);
    SelectObject(dc, op); SelectObject(dc, ob);
    DeleteObject(p); DeleteObject(br);
}

static void LandmarkLabel(HDC dc, int k)
{
    const char* s = LMS[k].name;
    int n = (int)strlen(s), x = NX(LMS[k].node), y = NY(LMS[k].node);
    SIZE sz; GetTextExtentPoint32A(dc, s, n, &sz);
    int tx, ty;
    switch (LMS[k].side) {
    case 0:  tx = x + 9;           ty = y - sz.cy / 2;  break;
    case 1:  tx = x - 9 - sz.cx;   ty = y - sz.cy / 2;  break;
    case 2:  tx = x - sz.cx / 2;   ty = y - 9 - sz.cy;  break;
    default: tx = x - sz.cx / 2;   ty = y + 9;          break;
    }
    SetTextColor(dc, RGB(255, 255, 255));                // white outline for readability
    for (int dx = -1; dx <= 1; dx++)
        for (int dy = -1; dy <= 1; dy++)
            if (dx || dy) TextOutA(dc, tx + dx, ty + dy, s, n);
    SetTextColor(dc, RGB(20, 20, 30));
    TextOutA(dc, tx, ty, s, n);
}

static void DrawHeart(HDC dc, int cx, int cy, int sz)
{
    POINT p[48];
    for (int i = 0; i < 48; i++) {
        double t = i * 2.0 * 3.14159265358979 / 48.0;
        double x = 16.0 * pow(sin(t), 3.0);
        double y = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t));
        p[i].x = cx + (int)floor(x * sz / 16.0 + 0.5);
        p[i].y = cy + (int)floor(y * sz / 16.0 + 0.5);
    }
    HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    HBRUSH br = CreateSolidBrush(RGB(230, 30, 100));
    HGDIOBJ op = SelectObject(dc, pen), ob = SelectObject(dc, br);
    Polygon(dc, p, 48);
    SelectObject(dc, op); SelectObject(dc, ob);
    DeleteObject(pen); DeleteObject(br);
}

static void DrawStar(HDC dc, int cx, int cy, int r)
{
    POINT p[10];
    for (int i = 0; i < 10; i++) {
        double ang = -3.14159265358979 / 2.0 + i * 3.14159265358979 / 5.0;
        double rr = (i % 2 == 0) ? r : r * 0.42;               // outer and inner points
        p[i].x = cx + (int)floor(rr * cos(ang) + 0.5);
        p[i].y = cy + (int)floor(rr * sin(ang) + 0.5);
    }
    HPEN pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    HBRUSH br = CreateSolidBrush(RGB(255, 190, 20));
    HGDIOBJ op = SelectObject(dc, pen), ob = SelectObject(dc, br);
    Polygon(dc, p, 10);
    SelectObject(dc, op); SelectObject(dc, ob);
    DeleteObject(pen); DeleteObject(br);
}

static void FavLabel(HDC dc, int i)
{
    const char* s = FavNameAt(i);
    int n = (int)strlen(s), x = NX(FavNodeAt(i)), y = NY(FavNodeAt(i));
    SIZE sz; GetTextExtentPoint32A(dc, s, n, &sz);
    int tx = x - sz.cx / 2, ty = y + 7;
    SetTextColor(dc, RGB(255, 255, 255));
    for (int dx = -1; dx <= 1; dx++)
        for (int dy = -1; dy <= 1; dy++)
            if (dx || dy) TextOutA(dc, tx + dx, ty + dy, s, n);
    SetTextColor(dc, FavTypeAt(i) == 'S' ? RGB(150, 95, 0) : RGB(170, 20, 85));
    TextOutA(dc, tx, ty, s, n);
}

static void Text(HDC dc, int x, int y, const char* s, COLORREF c, HFONT f)
{
    SelectObject(dc, f); SetTextColor(dc, c);
    TextOutA(dc, x, y, s, (int)strlen(s));
}

static void Paint(HDC dc, RECT rc)
{
    SetBkMode(dc, TRANSPARENT);

    // ---- map picture ----
    if (hMapDC) {
        if (mapW == MAP_W && mapH == MAP_H) BitBlt(dc, 0, 0, MAP_W, MAP_H, hMapDC, 0, 0, SRCCOPY);
        else { SetStretchBltMode(dc, HALFTONE); StretchBlt(dc, 0, 0, MAP_W, MAP_H, hMapDC, 0, 0, mapW, mapH, SRCCOPY); }
    } else {
        HBRUSH bg = CreateSolidBrush(RGB(236, 232, 222));
        RECT mr = { 0, 0, MAP_W, MAP_H };
        FillRect(dc, &mr, bg); DeleteObject(bg);
        Text(dc, 20, 20, "karachi_map.bmp not found - put it in the project folder (next to main.cpp).", RGB(180, 20, 30), fBold);
    }
    if (started) {                                       // fade the map so the search stands out
        HDC wd = CreateCompatibleDC(dc);
        HBITMAP wb = CreateCompatibleBitmap(dc, 1, 1);
        HGDIOBJ ow = SelectObject(wd, wb);
        SetPixel(wd, 0, 0, RGB(255, 255, 255));
        BLENDFUNCTION bf = { AC_SRC_OVER, 0, 105, 0 };
        AlphaBlend(dc, 0, 0, MAP_W, MAP_H, wd, 0, 0, 1, 1, bf);
        SelectObject(wd, ow); DeleteObject(wb); DeleteDC(wd);
    }

    // ---- search animation ----
    if (started) {
        HPEN penTree  = CreatePen(PS_SOLID, 4, RGB(30, 100, 230));
        HPEN penRelax = CreatePen(PS_SOLID, 5, RGB(255, 140, 0));
        HGDIOBJ old = SelectObject(dc, penTree);
        for (int v = 0; v < NNODES; v++)                 // shortest-route tree found so far
            if (GetVisited(v) && GetPrev(v) >= 0) {
                int e = edgeOf[GetPrev(v)][v];
                if (e >= 0) DrawEdge(dc, e);
            }
        SelectObject(dc, penRelax);
        if (lastU >= 0)                                  // roads just checked from the current node
            for (int e = 0; e < NEDGES; e++) {
                int a = EDGE_U[e], b = EDGE_V[e], o = -1;
                if (a == lastU) o = b; else if (b == lastU) o = a;
                if (o >= 0 && !GetVisited(o)) DrawEdge(dc, e);
            }
        SelectObject(dc, old);
        DeleteObject(penTree); DeleteObject(penRelax);

        for (int i = 0; i < NNODES; i++) {               // junction dots
            if (GetVisited(i))          Disc(dc, NX(i), NY(i), 3, RGB(30, 100, 230), RGB(255, 255, 255), 1);
            else if (GetDist(i) < 9999) Disc(dc, NX(i), NY(i), 3, RGB(250, 215, 60), RGB(120, 100, 0), 1);
        }
        if (lastU >= 0) Disc(dc, NX(lastU), NY(lastU), 7, RGB(255, 140, 0), RGB(255, 255, 255), 2);
    }

    // ---- final route ----
    if (state == DONE && pathLen > 1) {
        HPEN under = CreatePen(PS_SOLID, 11, RGB(255, 255, 255));
        HPEN red   = CreatePen(PS_SOLID, 6, RGB(225, 25, 40));
        HGDIOBJ old = SelectObject(dc, under);
        for (int pass = 0; pass < 2; pass++) {
            for (int i = 0; i + 1 < pathLen; i++) {
                int e = edgeOf[GetPathNode(i)][GetPathNode(i + 1)];
                if (e >= 0) DrawEdge(dc, e);
            }
            SelectObject(dc, red);
        }
        SelectObject(dc, old);
        DeleteObject(under); DeleteObject(red);
    }

    // ---- landmarks ----
    for (int k = 0; k < NLM; k++) {
        int n = LMS[k].node;
        if (LMS[k].major) Disc(dc, NX(n), NY(n), 5, RGB(255, 255, 255), RGB(40, 40, 60), 2);
        else              Disc(dc, NX(n), NY(n), 3, RGB(255, 255, 255), RGB(70, 70, 90), 1);
    }
    if (src >= 0) Disc(dc, NX(src), NY(src), 10, RGB(40, 180, 80), RGB(255, 255, 255), 3);
    if (dst >= 0) Disc(dc, NX(dst), NY(dst), 10, RGB(220, 30, 40), RGB(255, 255, 255), 3);
    SelectObject(dc, fLm);
    for (int k = 0; k < NLM; k++)
        if (LMS[k].major || showAll || LMS[k].node == src || LMS[k].node == dst) LandmarkLabel(dc, k);
    if (hoverLm >= 0) LandmarkLabel(dc, hoverLm);        // name of the dot under the mouse

    // ---- favourites: heart + name ----
    for (int i = 0; i < FavCount(); i++) {
        if (FavTypeAt(i) == 'S') DrawStar(dc, NX(FavNodeAt(i)), NY(FavNodeAt(i)) - 12, 12);
        else                     DrawHeart(dc, NX(FavNodeAt(i)), NY(FavNodeAt(i)) - 12, 10);
    }
    SelectObject(dc, fLm);
    for (int i = 0; i < FavCount(); i++) FavLabel(dc, i);
    if (pendingNode >= 0)                                // point chosen with the right mouse button
        Disc(dc, NX(pendingNode), NY(pendingNode), 9, RGB(255, 205, 225), RGB(220, 40, 120), 3);

    // map credit (required by OpenStreetMap)
    RECT cr = { MAP_W - 214, MAP_H - 18, MAP_W, MAP_H };
    HBRUSH wbr = CreateSolidBrush(RGB(255, 255, 255));
    FillRect(dc, &cr, wbr); DeleteObject(wbr);
    Text(dc, MAP_W - 210, MAP_H - 17, "Map data (c) OpenStreetMap contributors", RGB(60, 60, 60), fSmall);

    // name bar for saving a favourite (the edit box and buttons are real child windows)
    if (pendingNode >= 0) {
        RECT br2 = { 10, 640, 600, 684 };
        HBRUSH wb2 = CreateSolidBrush(RGB(255, 255, 255));
        HPEN bp = CreatePen(PS_SOLID, 2, RGB(220, 40, 120));
        HGDIOBJ obp = SelectObject(dc, bp), obb = SelectObject(dc, wb2);
        Rectangle(dc, br2.left, br2.top, br2.right, br2.bottom);
        SelectObject(dc, obp); SelectObject(dc, obb);
        DeleteObject(bp); DeleteObject(wb2);
        Text(dc, 20, 654, pendingFav >= 0 ? "Edit:" : "Name it:", RGB(170, 20, 85), fBold);
    }

    // ---------- side panel ----------
    RECT pr = { MAP_W, 0, rc.right, rc.bottom };
    HBRUSH pb = CreateSolidBrush(RGB(250, 250, 252));
    FillRect(dc, &pr, pb); DeleteObject(pb);
    HPEN lp = CreatePen(PS_SOLID, 1, RGB(200, 200, 205));
    HGDIOBJ olp = SelectObject(dc, lp);
    MoveToEx(dc, MAP_W, 0, NULL); LineTo(dc, MAP_W, rc.bottom);
    SelectObject(dc, olp); DeleteObject(lp);

    int X = MAP_W + 20;
    Text(dc, X, 14, "Karachi Route Finder", RGB(20, 20, 20), fTitle);
    Text(dc, X, 44, "Dijkstra's algorithm in x86 assembly", RGB(110, 110, 110), fSmall);
    {
        char t[80]; sprintf_s(t, "%d areas: hover a dot to see its name", NLM);
        Text(dc, X, 60, t, RGB(110, 110, 110), fSmall);
    }
    Text(dc, X, 78, "From:", RGB(60, 60, 60), fBold);
    Text(dc, X, 128, "To:", RGB(60, 60, 60), fBold);

    RECT sr = { X, 290, rc.right - 15, 336 };
    SelectObject(dc, fSmall); SetTextColor(dc, RGB(30, 80, 160));
    DrawTextA(dc, gMsg, -1, &sr, DT_WORDBREAK);

    char b[1600]; int y = 340;
    if (started) {
        sprintf_s(b, "Step %d   (junctions finalised so far)", steps);
        Text(dc, X, y, b, RGB(60, 60, 60), fSmall);
    }
    y += 22;
    if (state == DONE && pathLen > 0) {
        int d = GetDist(dst);
        sprintf_s(b, "Distance: %d.%d km", d / 10, d % 10);
        Text(dc, X, y, b, RGB(180, 20, 30), fBold); y += 22;
        sprintf_s(b, "Time: about %d min at 30 km/h", d / 5);
        Text(dc, X, y, b, RGB(60, 60, 60), fSmall); y += 24;
        RouteString(b);
        RECT rr = { X, y, rc.right - 15, y + 80 };
        SelectObject(dc, fSmall); SetTextColor(dc, RGB(40, 40, 40));
        DrawTextA(dc, b, -1, &rr, DT_WORDBREAK);
    }

    sprintf_s(b, "Saved routes in file: %d", HistCount());
    Text(dc, X, 478, b, RGB(60, 60, 60), fBold);
    if (HistRecentN() == 0) Text(dc, X, 500, "(none yet)", RGB(130, 130, 130), fSmall);
    for (int k = 0; k < HistRecentN(); k++) {
        RECT lr = { X, 500 + k * 18, rc.right - 12, 516 + k * 18 };
        SelectObject(dc, fSmall); SetTextColor(dc, RGB(70, 70, 70));
        DrawTextA(dc, HistRecentAt(k), -1, &lr, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    }

    // legend
    int ly = 558;
    struct { COLORREF c; const char* t; } leg[] = {
        {RGB(255,140,0), "Junction being processed"},
        {RGB(30,100,230), "Finalised (shortest-route tree)"}, {RGB(250,215,60), "Discovered, not final yet"}
    };
    {   // row 0: start and stop side by side
        HBRUSH g1 = CreateSolidBrush(RGB(40, 180, 80)), g2 = CreateSolidBrush(RGB(220, 30, 40));
        HGDIOBJ o1 = SelectObject(dc, g1);
        Ellipse(dc, X, ly, X + 12, ly + 12);
        SelectObject(dc, g2);
        Ellipse(dc, X + 90, ly, X + 102, ly + 12);
        SelectObject(dc, o1); DeleteObject(g1); DeleteObject(g2);
        Text(dc, X + 20, ly - 2, "Start", RGB(70, 70, 70), fSmall);
        Text(dc, X + 110, ly - 2, "Stop", RGB(70, 70, 70), fSmall);
    }
    for (int i = 0; i < 3; i++) {
        int yy = ly + (i + 1) * 17;
        HBRUSH lb = CreateSolidBrush(leg[i].c);
        HGDIOBJ o1 = SelectObject(dc, lb);
        Ellipse(dc, X, yy, X + 12, yy + 12);
        SelectObject(dc, o1); DeleteObject(lb);
        Text(dc, X + 20, yy - 2, leg[i].t, RGB(70, 70, 70), fSmall);
    }
    HPEN rp = CreatePen(PS_SOLID, 5, RGB(225, 25, 40));
    HGDIOBJ orp = SelectObject(dc, rp);
    MoveToEx(dc, X, ly + 4 * 17 + 6, NULL); LineTo(dc, X + 13, ly + 4 * 17 + 6);
    SelectObject(dc, orp); DeleteObject(rp);
    Text(dc, X + 20, ly + 4 * 17 - 2, "Final shortest route", RGB(70, 70, 70), fSmall);
    DrawHeart(dc, X + 6, ly + 5 * 17 + 6, 7);
    Text(dc, X + 20, ly + 5 * 17 - 2, "Home", RGB(70, 70, 70), fSmall);
    DrawStar(dc, X + 96, ly + 5 * 17 + 6, 8);
    Text(dc, X + 110, ly + 5 * 17 - 2, "Other saved place", RGB(70, 70, 70), fSmall);
    Text(dc, X, 664, "Right-click a place = save heart / star", RGB(130, 130, 130), fSmall);
    Text(dc, X, 681, "Up/Down: speed     L: all labels", RGB(130, 130, 130), fSmall);
}

// ---------- window procedure ----------
static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WM_CREATE: {
        hMain = h;
        fSmall = CreateFontA(15, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Segoe UI");
        fBold  = CreateFontA(15, 0, 0, 0, FW_BOLD,   0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Segoe UI");
        fTitle = CreateFontA(22, 0, 0, 0, FW_BOLD,   0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Segoe UI");
        fLm    = CreateFontA(14, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, "Segoe UI");
        int X = MAP_W + 20;
        // drop-down lists of every area (you can also just type a name)
        hFrom  = CreateWindowA("COMBOBOX", "", WS_CHILD | WS_VISIBLE | WS_VSCROLL | CBS_DROPDOWN | CBS_AUTOHSCROLL | CBS_SORT, X, 98, 260, 280, h, NULL, NULL, NULL);
        hTo    = CreateWindowA("COMBOBOX", "", WS_CHILD | WS_VISIBLE | WS_VSCROLL | CBS_DROPDOWN | CBS_AUTOHSCROLL | CBS_SORT, X, 148, 260, 280, h, NULL, NULL, NULL);
        // name bar for favourites (hidden until you right-click a place)
        hFavEdit   = CreateWindowA("EDIT", "", WS_CHILD | WS_BORDER | ES_AUTOHSCROLL, 84, 650, 168, 24, h, NULL, NULL, NULL);
        hFavSave   = CreateWindowA("BUTTON", "Save as Heart", WS_CHILD | BS_PUSHBUTTON, 258, 648, 106, 28, h, (HMENU)ID_FSAVE, NULL, NULL);
        hFavStar   = CreateWindowA("BUTTON", "Save as Star", WS_CHILD | BS_PUSHBUTTON, 368, 648, 100, 28, h, (HMENU)ID_FSTAR, NULL, NULL);
        hFavDel    = CreateWindowA("BUTTON", "Delete", WS_CHILD | BS_PUSHBUTTON, 474, 648, 62, 28, h, (HMENU)ID_FDEL, NULL, NULL);
        hFavCancel = CreateWindowA("BUTTON", "Cancel", WS_CHILD | BS_PUSHBUTTON, 540, 648, 56, 28, h, (HMENU)ID_FCANCEL, NULL, NULL);
        SendMessageA(hFavEdit, EM_LIMITTEXT, 40, 0);
        SendMessageA(hFavEdit,   WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hFavSave,   WM_SETFONT, (WPARAM)fBold,  TRUE);
        SendMessageA(hFavStar,   WM_SETFONT, (WPARAM)fBold,  TRUE);
        SendMessageA(hFavDel,    WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hFavCancel, WM_SETFONT, (WPARAM)fSmall, TRUE);
        hGo    = CreateWindowA("BUTTON", "Find route", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X, 188, 125, 32, h, (HMENU)ID_GO, NULL, NULL);
        hReset = CreateWindowA("BUTTON", "Reset", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X + 135, 188, 125, 32, h, (HMENU)ID_RESET, NULL, NULL);
        hHist  = CreateWindowA("BUTTON", "View history file", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X, 222, 125, 28, h, (HMENU)ID_HIST, NULL, NULL);
        hClear = CreateWindowA("BUTTON", "Clear history", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X + 135, 222, 125, 28, h, (HMENU)ID_CLEAR, NULL, NULL);
        hFavView  = CreateWindowA("BUTTON", "View favourites", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X, 254, 125, 28, h, (HMENU)ID_FAVVIEW, NULL, NULL);
        hFavClear = CreateWindowA("BUTTON", "Clear favourites", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, X + 135, 254, 125, 28, h, (HMENU)ID_FAVCLEAR, NULL, NULL);
        SendMessageA(hFrom,  WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hTo,    WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hGo,    WM_SETFONT, (WPARAM)fBold,  TRUE);
        SendMessageA(hReset, WM_SETFONT, (WPARAM)fBold,  TRUE);
        SendMessageA(hHist,  WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hClear, WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hFavView,  WM_SETFONT, (WPARAM)fSmall, TRUE);
        SendMessageA(hFavClear, WM_SETFONT, (WPARAM)fSmall, TRUE);

        LoadMapBitmap();
        InitMapData();                                   // map -> assembly, then it reads favourites.txt and route_history.txt
        FillPlaceLists();
        SetMsg(hMapDC ? "Click a place on the map (or type names) to choose the START."
                      : "karachi_map.bmp was not found. Copy it into the project folder and restart.");
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(w) == ID_GO) OnGo();
        else if (LOWORD(w) == ID_FSAVE) SaveFav('H');
        else if (LOWORD(w) == ID_FSTAR) SaveFav('S');
        else if (LOWORD(w) == ID_FDEL) DeleteFav();
        else if (LOWORD(w) == ID_FCANCEL) CloseFavBar();
        else if (LOWORD(w) == ID_RESET) ResetAll();
        else if (LOWORD(w) == ID_HIST) {
            HistLoad();                                  // assembly: re-read the file
            if (HistCount() == 0) {
                MessageBoxA(h, "No routes saved yet. Find a route first.", "History", MB_OK);
            } else {
                char q[MAX_PATH + 4];
                sprintf_s(q, "\"%s\"", GetHistPath());
                ShellExecuteA(h, "open", "notepad.exe", q, NULL, SW_SHOWNORMAL);
            }
        }
        else if (LOWORD(w) == ID_FAVVIEW) {
            if (FavCount() == 0) {
                MessageBoxA(h, "No favourites saved yet.\n\nRight-click a place on the map to save it as a Heart (home) or a Star (other place).", "Favourites", MB_OK | MB_ICONINFORMATION);
            } else {
                char list[4000]; list[0] = 0;
                for (int i = 0; i < FavCount(); i++) {
                    char line[200];
                    sprintf_s(line, "%2d.  [%s]  %s\n", i + 1, FavTypeAt(i) == 'S' ? "Star" : "Heart", FavNameAt(i));
                    strncat_s(list, sizeof(list), line, _TRUNCATE);
                }
                strncat_s(list, sizeof(list), "\nOpen favourites.txt in Notepad?", _TRUNCATE);
                if (MessageBoxA(h, list, "My favourites", MB_YESNO | MB_ICONINFORMATION) == IDYES) {
                    char q[MAX_PATH + 4];
                    sprintf_s(q, "\"%s\"", GetFavPath());
                    ShellExecuteA(h, "open", "notepad.exe", q, NULL, SW_SHOWNORMAL);
                }
            }
        }
        else if (LOWORD(w) == ID_FAVCLEAR) {
            if (FavCount() > 0 && MessageBoxA(h, "Delete ALL favourite places (hearts and stars)?", "Clear favourites", MB_YESNO | MB_ICONQUESTION) == IDYES) {
                FavClearAll();                           // assembly
                FillPlaceLists();
                CloseFavBar();
                SetMsg("All favourites removed.");
                InvalidateRect(h, NULL, FALSE);
            }
        }
        else if (LOWORD(w) == ID_CLEAR) {
            if (MessageBoxA(h, "Delete all saved routes?", "Clear history", MB_YESNO | MB_ICONQUESTION) == IDYES) {
                ClearHistory();                          // assembly
                InvalidateRect(h, NULL, FALSE);
            }
        }
        return 0;
    case WM_LBUTTONDOWN: {
        int x = LOWORD(l), y = HIWORD(l);
        if (x < MAP_W && y < MAP_H) {
            SetFocus(h);
            int n = HitNode(x, y);                       // assembly: which junction was clicked
            if (n >= 0) OnPick(n);
        }
        return 0;
    }
    case WM_RBUTTONDOWN: {
        int x = LOWORD(l), y = HIWORD(l);
        if (x < MAP_W && y < MAP_H) {
            int n = HitNode(x, y);                       // assembly: which junction was clicked
            if (n >= 0) OpenFavBar(n);
        }
        return 0;
    }
    case WM_TIMER:
        if (w == 1 && state == RUNNING) Tick();
        return 0;
    case WM_MOUSEMOVE: {
        int x = LOWORD(l), y = HIWORD(l), nh = -1;
        if (x < MAP_W && y < MAP_H) nh = HitLandmark(x, y, 12 * 12);   // assembly: area dot under the mouse
        if (nh != hoverLm) { hoverLm = nh; InvalidateRect(h, NULL, FALSE); }
        return 0;
    }
    case WM_KEYDOWN:
        if (w == VK_UP   && speedIdx < 5) speedIdx++;
        if (w == VK_DOWN && speedIdx > 0) speedIdx--;
        if (w == 'L') { showAll = !showAll; InvalidateRect(h, NULL, FALSE); }
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps);
        RECT rc; GetClientRect(h, &rc);
        HDC mem = CreateCompatibleDC(dc);
        HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom);
        HGDIOBJ old = SelectObject(mem, bmp);
        Paint(mem, rc);
        BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
        SelectObject(mem, old); DeleteObject(bmp); DeleteDC(mem);
        EndPaint(h, &ps);
        return 0;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(h, m, w, l);
}

int main()
{
    HINSTANCE hi = GetModuleHandleA(NULL);
    WNDCLASSA wc = { 0 };
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hi;
    wc.hCursor = LoadCursorA(NULL, MAKEINTRESOURCEA(32512));   // IDC_ARROW
    wc.lpszClassName = "KarachiRouteWnd";
    RegisterClassA(&wc);

    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;
    RECT r = { 0, 0, WIN_W, WIN_H };
    AdjustWindowRect(&r, style, FALSE);
    HWND h = CreateWindowA("KarachiRouteWnd", "Karachi Route Finder - Dijkstra (COAL Project)",
                           style, CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top,
                           NULL, NULL, hi, NULL);
    ShowWindow(h, SW_SHOW);
    UpdateWindow(h);

    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return 0;
}
