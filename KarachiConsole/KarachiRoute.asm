TITLE Karachi Route Finder - Dijkstra on a Grid Map (MASM / Irvine32)
; ============================================================
; EL-2003 COAL Lab - Semester Project, Fall 2026
; Group GR1 : Ali Adeel (25K-2528), Muhammad Talha (25K-2500),
;             Talha Yousuf (25K-2533)
;
; The city is a 40 x 18 grid. Each cell is one of:
;   '~' sea (blocked)   '#' blocked zone
;   '=' main road  cost 1
;   '+' busy road  cost 3
;   '.' narrow lane cost 5
; 12 numbered landmarks sit on road cells. Dijkstra's algorithm
; (4 neighbours per cell) finds the cheapest route; the search
; is animated and the final route is highlighted.
; ============================================================
INCLUDE Irvine32.inc

MAPW     = 40
MAPH     = 18
NCELLS   = MAPW * MAPH
MAPY     = 1                     ; screen row of the first map row
NLM      = 12                    ; number of landmarks
INF      = 1000000

; Cursor helper: mGoto column, row   (EDX is preserved)
mGoto MACRO x, y
    push edx
    mov  dl, x
    mov  dh, y
    call Gotoxy
    pop  edx
ENDM

.data
; ---------- messages ----------
title1     BYTE "KARACHI ROUTE FINDER - Dijkstra's Algorithm (x86 Assembly)",0
legTitle   BYTE "LANDMARKS",0
dotSp      BYTE "  ",0
menuMsg    BYTE "1. Find route   2. Exit   Choice: ",0
promptSrc  BYTE "Source landmark (1-12)     : ",0
promptDst  BYTE "Destination landmark (1-12): ",0
errInvalid BYTE "Invalid input. Please enter a number in the valid range.",0
errSame    BYTE "Source and destination are the same place - nothing to travel.",0
errNoRoute BYTE "No route found between these landmarks.",0
costMsg    BYTE "Total travel cost : ",0
passMsg    BYTE "Landmarks passed  : ",0
arrowMsg   BYTE " -> ",0
pressMsg   BYTE "Press any key to continue...",0

lgMain     BYTE " Main road   (cost 1)",0
lgBusy     BYTE " Busy road   (cost 3)",0
lgNarrow   BYTE " Narrow lane (cost 5)",0
lgBlock    BYTE " Blocked zone",0
lgSea      BYTE " Sea",0
lgExplore  BYTE " Explored by search",0
lgPath     BYTE " Final route",0
lgSrc      BYTE " Source",0
lgDst      BYTE " Destination",0

; ---------- landmarks ----------
nm0   BYTE "Saddar",0
nm1   BYTE "Clifton",0
nm2   BYTE "DHA",0
nm3   BYTE "Gulshan-e-Iqbal",0
nm4   BYTE "Jinnah Airport",0
nm5   BYTE "North Nazimabad",0
nm6   BYTE "SITE",0
nm7   BYTE "Keamari",0
nm8   BYTE "Korangi",0
nm9   BYTE "Malir",0
nm10  BYTE "Gulistan-e-Johar",0
nm11  BYTE "PECHS",0
lmName DWORD OFFSET nm0, OFFSET nm1, OFFSET nm2,  OFFSET nm3
       DWORD OFFSET nm4, OFFSET nm5, OFFSET nm6,  OFFSET nm7
       DWORD OFFSET nm8, OFFSET nm9, OFFSET nm10, OFFSET nm11
lmRow    BYTE 10, 13, 14,  5,  4,  2,  2, 11, 12,  8,  7,  8
lmCol    BYTE 12, 14, 22, 22, 34, 12,  4,  4, 31, 37, 30, 18
lmLabels BYTE "123456789ABC"

; ---------- the map: 18 rows x 40 columns, row-major ----------
mapTxt   BYTE "########################################"
         BYTE "########################################"
         BYTE "####+========###########################"
         BYTE "####+#######=###########################"
         BYTE "####+#######=#########============+#####"
         BYTE "####+#######..........=###########+#####"
         BYTE "####+#######=#########=###########+#####"
         BYTE "####+#######=#########=#######.....#####"
         BYTE "####+#######=#####=============###====##"
         BYTE "~~##+#######=#####+###############+#####"
         BYTE "~~##........======+===+========+==+#####"
         BYTE "~~##+#########=#######+########+########"
         BYTE "~~############=#######..........########"
         BYTE "~~~~~~~~~~####========+#################"
         BYTE "~~~~~~~~~~############=#################"
         BYTE "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
         BYTE "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
         BYTE "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

; ---------- working arrays ----------
lmGrid     BYTE NCELLS DUP(0)         ; landmark number (1..12) per cell
cellState  BYTE NCELLS DUP(0)         ; 0 normal, 1 explored, 2 on route
visited    BYTE NCELLS DUP(0)
dist       DWORD NCELLS DUP(INF)
prev       SDWORD NCELLS DUP(-1)
pathCells  DWORD NCELLS DUP(0)
passLm     DWORD 16 DUP(0)

dirR       SBYTE -1, 1, 0, 0          ; up, down, left, right
dirC       SBYTE  0, 0,-1, 1

srcCell    SDWORD -1
dstCell    SDWORD -1
srcIdx     DWORD ?
dstIdx     DWORD ?
curU       DWORD ?
uRow       DWORD ?
uCol       DWORD ?
dirIdx     DWORD ?
animCnt    DWORD 0
pathLen    DWORD 0
pathIdx    DWORD 0
passCnt    DWORD 0

.code
; ============================================================
main PROC
    call InitLandmarks
MenuLoop:
    call ResetView
    mov  eax, 7
    call SetTextColor
    call Clrscr
    call DrawAll
    mov  eax, 7
    call SetTextColor
    mGoto 0, 20
    mov  edx, OFFSET menuMsg
    call WriteString
    call ReadInt
    cmp  eax, 1
    je   DoFind
    cmp  eax, 2
    je   DoExit
    mov  edx, OFFSET errInvalid
    call ShowMessage
    jmp  MenuLoop
DoFind:
    call FindRoute
    jmp  MenuLoop
DoExit:
    mov  eax, 7
    call SetTextColor
    call Clrscr
    exit
main ENDP

; ============================================================
; ShowMessage : prints the string in EDX on row 23, then waits
; ============================================================
ShowMessage PROC
    push edx
    mGoto 0, 23
    mov  eax, 12                  ; light red text
    call SetTextColor
    pop  edx
    call WriteString
    call Crlf
    mov  eax, 7
    call SetTextColor
    call WaitKey
    ret
ShowMessage ENDP

WaitKey PROC
    mov  eax, 7
    call SetTextColor
    mGoto 0, 25
    mov  edx, OFFSET pressMsg
    call WriteString
    call ReadChar
    ret
WaitKey ENDP

; ============================================================
; InitLandmarks : mark every landmark cell in lmGrid
; ============================================================
InitLandmarks PROC
    pushad
    mov  esi, 0
ILLoop:
    cmp  esi, NLM
    jge  ILDone
    movzx eax, lmRow[esi]
    imul eax, MAPW
    movzx ebx, lmCol[esi]
    add  eax, ebx                 ; cell index
    mov  ecx, esi
    inc  ecx
    mov  lmGrid[eax], cl          ; store landmark number
    inc  esi
    jmp  ILLoop
ILDone:
    popad
    ret
InitLandmarks ENDP

; ============================================================
; ResetView : forget source/destination and the old search
; ============================================================
ResetView PROC
    pushad
    mov  srcCell, -1
    mov  dstCell, -1
    mov  esi, 0
RVLoop:
    cmp  esi, NCELLS
    jge  RVDone
    mov  cellState[esi], 0
    inc  esi
    jmp  RVLoop
RVDone:
    popad
    ret
ResetView ENDP

; ============================================================
; CostOfCell : ESI = cell index -> EAX = travel cost (0 = blocked)
; ============================================================
CostOfCell PROC
    movzx eax, mapTxt[esi]
    cmp  al, '='
    je   CCMain
    cmp  al, '+'
    je   CCBusy
    cmp  al, '.'
    je   CCNarrow
    mov  eax, 0
    ret
CCMain:
    mov  eax, 1
    ret
CCBusy:
    mov  eax, 3
    ret
CCNarrow:
    mov  eax, 5
    ret
CostOfCell ENDP

; ============================================================
; BgOfCell : ESI = cell index -> EAX = background colour (0-15)
; ============================================================
BgOfCell PROC
    cmp  esi, srcCell
    je   BgSrc
    cmp  esi, dstCell
    je   BgDst
    cmp  cellState[esi], 2
    je   BgPath
    cmp  cellState[esi], 1
    je   BgExp
    movzx eax, mapTxt[esi]
    cmp  al, '='
    je   BgMain
    cmp  al, '+'
    je   BgBusy
    cmp  al, '.'
    je   BgNarrow
    cmp  al, '~'
    je   BgSea
    mov  eax, 8                   ; '#' blocked zone: dark grey
    ret
BgSrc:
    mov  eax, 10                  ; light green
    ret
BgDst:
    mov  eax, 12                  ; light red
    ret
BgPath:
    mov  eax, 14                  ; yellow
    ret
BgExp:
    mov  eax, 11                  ; light cyan
    ret
BgMain:
    mov  eax, 15                  ; white
    ret
BgBusy:
    mov  eax, 6                   ; brown
    ret
BgNarrow:
    mov  eax, 7                   ; light grey
    ret
BgSea:
    mov  eax, 1                   ; blue
    ret
BgOfCell ENDP

; ============================================================
; DrawCell : ESI = cell index. Draws that one cell in colour.
; ============================================================
DrawCell PROC
    pushad
    mov  eax, esi
    mov  edx, 0
    mov  ebx, MAPW
    div  ebx                      ; EAX = row, EDX = column
    mov  dh, al
    add  dh, MAPY                 ; DH = screen row, DL = column
    call Gotoxy
    call BgOfCell                 ; EAX = background colour
    shl  eax, 4                   ; foreground 0 (black) + bg*16
    call SetTextColor
    movzx eax, lmGrid[esi]
    cmp  eax, 0
    jne  DCLabel
    mov  al, ' '
    jmp  DCPrint
DCLabel:
    dec  eax
    mov  al, lmLabels[eax]        ; '1'..'9','A'..'C'
DCPrint:
    call WriteChar
    popad
    ret
DrawCell ENDP

; ============================================================
; DrawAll : title, whole map and legend
; ============================================================
DrawAll PROC
    pushad
    mov  eax, 15
    call SetTextColor
    mGoto 0, 0
    mov  edx, OFFSET title1
    call WriteString
    mov  esi, 0
DALoop:
    cmp  esi, NCELLS
    jge  DADone
    call DrawCell
    inc  esi
    jmp  DALoop
DADone:
    call DrawLegend
    popad
    ret
DrawAll ENDP

; ============================================================
; LegendItem : EAX = background colour, EDX = text, ECX = row
; ============================================================
LegendItem PROC
    pushad
    push edx
    mov  dl, 42
    mov  dh, cl
    call Gotoxy
    shl  eax, 4
    call SetTextColor
    mov  al, ' '
    call WriteChar
    call WriteChar
    mov  eax, 7
    call SetTextColor
    pop  edx
    call WriteString
    popad
    ret
LegendItem ENDP

; ============================================================
; DrawLegend : landmark list and colour legend (right side)
; ============================================================
DrawLegend PROC
    pushad
    mov  eax, 15
    call SetTextColor
    mGoto 42, 0
    mov  edx, OFFSET legTitle
    call WriteString
    mov  eax, 7
    call SetTextColor
    mov  esi, 0
DLLoop:
    cmp  esi, NLM
    jge  DLColours
    mov  eax, esi
    inc  eax
    mov  dh, al                   ; row = 1 + index
    mov  dl, 42
    call Gotoxy
    mov  al, lmLabels[esi]
    call WriteChar
    mov  edx, OFFSET dotSp
    call WriteString
    mov  edx, lmName[esi*4]
    call WriteString
    inc  esi
    jmp  DLLoop
DLColours:
    mov  eax, 15
    mov  edx, OFFSET lgMain
    mov  ecx, 14
    call LegendItem
    mov  eax, 6
    mov  edx, OFFSET lgBusy
    mov  ecx, 15
    call LegendItem
    mov  eax, 7
    mov  edx, OFFSET lgNarrow
    mov  ecx, 16
    call LegendItem
    mov  eax, 8
    mov  edx, OFFSET lgBlock
    mov  ecx, 17
    call LegendItem
    mov  eax, 1
    mov  edx, OFFSET lgSea
    mov  ecx, 18
    call LegendItem
    mov  eax, 11
    mov  edx, OFFSET lgExplore
    mov  ecx, 19
    call LegendItem
    mov  eax, 14
    mov  edx, OFFSET lgPath
    mov  ecx, 20
    call LegendItem
    mov  eax, 10
    mov  edx, OFFSET lgSrc
    mov  ecx, 21
    call LegendItem
    mov  eax, 12
    mov  edx, OFFSET lgDst
    mov  ecx, 22
    call LegendItem
    popad
    ret
DrawLegend ENDP

; ============================================================
; FindRoute : read + validate input, run search, show result
; ============================================================
FindRoute PROC
    pushad
    mov  eax, 7
    call SetTextColor
    mGoto 0, 21
    mov  edx, OFFSET promptSrc
    call WriteString
    call ReadInt
    cmp  eax, 1
    jl   FRBad
    cmp  eax, NLM
    jg   FRBad
    dec  eax
    mov  srcIdx, eax

    mGoto 0, 22
    mov  edx, OFFSET promptDst
    call WriteString
    call ReadInt
    cmp  eax, 1
    jl   FRBad
    cmp  eax, NLM
    jg   FRBad
    dec  eax
    mov  dstIdx, eax

    mov  eax, srcIdx
    cmp  eax, dstIdx
    je   FRSame

    ; source cell = row * MAPW + col
    mov  ebx, srcIdx
    movzx eax, lmRow[ebx]
    imul eax, MAPW
    movzx ecx, lmCol[ebx]
    add  eax, ecx
    mov  srcCell, eax
    ; destination cell
    mov  ebx, dstIdx
    movzx eax, lmRow[ebx]
    imul eax, MAPW
    movzx ecx, lmCol[ebx]
    add  eax, ecx
    mov  dstCell, eax

    mov  esi, srcCell             ; show the two end points
    call DrawCell
    mov  esi, dstCell
    call DrawCell

    call RunDijkstra              ; animated search

    mov  ebx, dstCell
    cmp  dist[ebx*4], INF
    jl   FRFound
    mov  edx, OFFSET errNoRoute
    call ShowMessage
    jmp  FRDone
FRFound:
    call ShowPath
    call WaitKey
    jmp  FRDone
FRBad:
    mov  edx, OFFSET errInvalid
    call ShowMessage
    jmp  FRDone
FRSame:
    mov  edx, OFFSET errSame
    call ShowMessage
FRDone:
    popad
    ret
FindRoute ENDP

; ============================================================
; FindMin : EAX = unvisited cell with the smallest dist,
;           or -1 if none is reachable
; ============================================================
FindMin PROC
    push ebx
    push ecx
    push esi
    mov  eax, -1
    mov  ebx, INF
    mov  esi, 0
FMLoop:
    cmp  esi, NCELLS
    jge  FMDone
    cmp  visited[esi], 0
    jne  FMNext
    mov  ecx, dist[esi*4]
    cmp  ecx, ebx
    jge  FMNext
    mov  eax, esi
    mov  ebx, ecx
FMNext:
    inc  esi
    jmp  FMLoop
FMDone:
    pop  esi
    pop  ecx
    pop  ebx
    ret
FindMin ENDP

; ============================================================
; RunDijkstra : dist[] / visited[] / prev[] over the grid.
;   Cost of a move = travel cost of the cell being entered.
;   Each cell is coloured as soon as it is finalised.
; ============================================================
RunDijkstra PROC
    pushad
    mov  esi, 0                   ; ---- initialise ----
RDInit:
    cmp  esi, NCELLS
    jge  RDInitDone
    mov  dist[esi*4], INF
    mov  prev[esi*4], -1
    mov  visited[esi], 0
    mov  cellState[esi], 0
    inc  esi
    jmp  RDInit
RDInitDone:
    mov  esi, srcCell
    mov  dist[esi*4], 0
    mov  animCnt, 0

RDMain:
    call FindMin                  ; EAX = cheapest unvisited cell
    cmp  eax, -1
    je   RDDone                   ; nothing left: destination unreachable
    mov  curU, eax
    mov  esi, eax
    mov  visited[esi], 1
    mov  cellState[esi], 1        ; explored
    call DrawCell                 ; animation
    inc  animCnt
    test animCnt, 1               ; pause on every 2nd cell
    jnz  RDNoDelay
    mov  eax, 10
    call Delay
RDNoDelay:
    mov  eax, curU
    cmp  eax, dstCell
    je   RDDone                   ; destination finalised: stop

    mov  edx, 0                   ; row / column of the current cell
    mov  ebx, MAPW
    div  ebx
    mov  uRow, eax
    mov  uCol, edx

    mov  dirIdx, 0                ; ---- relax the 4 neighbours ----
RDDir:
    cmp  dirIdx, 4
    jge  RDMain
    mov  ebx, dirIdx
    movsx eax, dirR[ebx]
    add  eax, uRow                ; neighbour row
    movsx ecx, dirC[ebx]
    add  ecx, uCol                ; neighbour column
    cmp  eax, 0
    jl   RDNext                   ; outside the grid
    cmp  eax, MAPH
    jge  RDNext
    cmp  ecx, 0
    jl   RDNext
    cmp  ecx, MAPW
    jge  RDNext
    imul eax, MAPW
    add  eax, ecx
    mov  edi, eax                 ; EDI = neighbour index
    cmp  visited[edi], 0
    jne  RDNext
    mov  esi, edi
    call CostOfCell               ; EAX = cost (0 = blocked)
    cmp  eax, 0
    je   RDNext
    mov  ebx, curU
    add  eax, dist[ebx*4]         ; alt = dist[u] + cost
    cmp  eax, dist[edi*4]
    jge  RDNext
    mov  dist[edi*4], eax         ; cheaper route found
    mov  prev[edi*4], ebx
RDNext:
    inc  dirIdx
    jmp  RDDir
RDDone:
    popad
    ret
RunDijkstra ENDP

; ============================================================
; ShowPath : rebuild the route from prev[], highlight it and
;            print the total cost and the landmarks passed
; ============================================================
ShowPath PROC
    pushad
    mov  pathLen, 0               ; trace destination -> source
    mov  esi, dstCell
SPTrace:
    cmp  esi, -1
    je   SPTraced
    mov  ebx, pathLen
    mov  pathCells[ebx*4], esi
    inc  pathLen
    mov  esi, prev[esi*4]
    jmp  SPTrace
SPTraced:
    mov  passCnt, 0
    mov  eax, pathLen
    dec  eax
    mov  pathIdx, eax             ; walk source -> destination
SPWalk:
    cmp  pathIdx, 0
    jl   SPWalked
    mov  ebx, pathIdx
    mov  esi, pathCells[ebx*4]
    mov  cellState[esi], 2
    call DrawCell                 ; highlight
    movzx eax, lmGrid[esi]
    cmp  eax, 0
    je   SPNoLm
    dec  eax                      ; landmark index 0..11
    mov  ebx, passCnt
    mov  passLm[ebx*4], eax
    inc  passCnt
SPNoLm:
    mov  eax, 25
    call Delay
    dec  pathIdx
    jmp  SPWalk
SPWalked:
    mov  eax, 7
    call SetTextColor
    mGoto 0, 23
    mov  edx, OFFSET costMsg
    call WriteString
    mov  ebx, dstCell
    mov  eax, dist[ebx*4]
    call WriteDec
    call Crlf
    mGoto 0, 24
    mov  edx, OFFSET passMsg
    call WriteString
    mov  esi, 0
SPPrint:
    cmp  esi, passCnt
    jge  SPEnd
    cmp  esi, 0
    je   SPName
    mov  edx, OFFSET arrowMsg
    call WriteString
SPName:
    mov  eax, passLm[esi*4]
    mov  edx, lmName[eax*4]
    call WriteString
    inc  esi
    jmp  SPPrint
SPEnd:
    call Crlf
    popad
    ret
ShowPath ENDP

END main
