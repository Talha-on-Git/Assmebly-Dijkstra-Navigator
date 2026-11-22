KARACHI ROUTE FINDER - Dijkstra-Based Shortest-Path Navigator in x86 Assembly
EL-2003 COAL Lab, Fall 2026 - Group GR1, Section BDS-3A
Ali Adeel (25K-2528), Muhammad Talha (25K-2500), Talha Yousuf (25K-2533)

The project has two programs:

1) KarachiGUI  (final project: map window, animated search, highlighted route, files)
   DijkstraCore.asm  - x86 assembly (MASM): graph, Dijkstra, name search, clicks, favourites,
                       route history, text/number handling and all file handling
   main.cpp          - C++ window and drawing only (Win32 API + GDI); calls the assembly procedures
   MapData.h         - generated map data (junctions, roads, road shapes, 78 areas)
   karachi_map.bmp   - OpenStreetMap picture of Karachi (c) OpenStreetMap contributors
   Files created while running (in the program working folder):
     route_history.txt - one line per shortest route found (button: View history file)
     favourites.txt    - favourite places, one per line:  x|y|H|name  (H = heart, S = star)  (buttons: View favourites / Clear favourites)

2) KarachiConsole  (first version from the proposal: 40 x 18 colour grid map, Irvine32)
   KarachiRoute.asm  - complete program in x86 assembly using the Irvine32 library

HOW TO BUILD AND RUN THE GUI VERSION (Visual Studio 2022)
 1. File > New > Project > "Empty Project" (C++).
 2. Set the platform to x86 (Win32), not x64.
 3. Right-click the project > Build Dependencies > Build Customizations > tick "masm".
 4. Add DijkstraCore.asm and main.cpp to the project (Add > Existing Item). Check that the
    Item Type of DijkstraCore.asm is "Microsoft Macro Assembler".
 5. Copy MapData.h and karachi_map.bmp into the project folder (the folder of main.cpp).
    Irvine32 is NOT needed for this version.
 6. Build, then run with Ctrl+F5.
 Using it: click two places (start, then stop), or type / pick names in the From and To lists and
 press "Find route". Right-click a place to save it as a Heart (home) or a Star (other place).
 Up / Down arrow = faster / slower search, L = show all area names, "View history file" opens
 route_history.txt. If karachi_map.bmp is not found, a window asks you to select it.

HOW TO BUILD AND RUN THE CONSOLE VERSION
 Use the usual Irvine32 project (Irvine32.inc and Irvine32.lib set up as in the lab manuals),
 add KarachiRoute.asm, build and run. Use a console window of at least 120 x 30 characters.

TESTS (optional, tests folder)
 harness.c is an automated test program (114 checks) that loads the real map into
 DijkstraCore.asm and calls its procedures. It was built on Linux (32-bit) with the Windows API
 file/time functions replaced by small stand-ins, so it cannot be run directly on Windows.
 The results are summarised in Section 6 of the report.

TOOLS / CREDITS
 MASM, Visual Studio 2022, Irvine32 (console version only), Windows API (kernel32, GDI).
 Map picture: OpenStreetMap contributors. An AI assistant was used (see Section 10 of the report).
