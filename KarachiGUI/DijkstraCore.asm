; ============================================================
; DijkstraCore.asm  -  all data, string and file logic of the
; Karachi Route Finder, written in x86 assembly (MASM, 32-bit).
;
; C++ (main.cpp) only opens the window and draws. It calls these
; procedures (C calling convention, result in EAX):
;
;   GRAPH      GraphReset, GraphAddEdge, SetNodePos, AddLandmark, DataInit
;   DIJKSTRA   DijkstraInit, DijkstraStep, GetDist, GetPrev, GetVisited
;   ROUTE      BuildPath, GetPathLen, GetPathNode, RouteString
;   MAP        NodeSX, NodeSY, HitLandmark, HitNode, NodeName
;   PLACES     PlaceCount, PlaceNameAt, PlaceNodeAt, FindPlace
;   FAVOURITES FavSet, FavDelete, FavCount, FavNodeAt, FavTypeAt,
;              FavNameAt, FavOfNodeAt, FavClearAll, GetFavPath   (stored in favourites.txt)
;   HISTORY    HistAppend, HistLoad, ClearHistory, HistCount,
;              HistRecentN, HistRecentAt (stored in route_history.txt)
;   FILES      AppendToFile, ReadWholeFile, ClearFile, CountLines
;
; Distances are in units of 0.1 km.
; ============================================================
.386
.model flat, C

INF      = 9999
MAXN     = 512            ; junctions
MAXLM    = 128            ; named areas
MAXFAV   = 64             ; favourite places
NAMELEN  = 48             ; bytes reserved for one favourite name

; ---- Windows file / time API (called straight from assembly) ----
INCLUDELIB kernel32.lib
CreateFileA          PROTO STDCALL, lpFileName:PTR BYTE, dwAccess:DWORD, dwShare:DWORD, lpSec:DWORD, dwCreate:DWORD, dwAttr:DWORD, hTemp:DWORD
SetFilePointer       PROTO STDCALL, hFile:DWORD, lDistance:SDWORD, lpHigh:DWORD, dwMethod:DWORD
GetFileSize          PROTO STDCALL, hFile:DWORD, lpHigh:DWORD
WriteFile            PROTO STDCALL, hFile:DWORD, lpBuffer:PTR BYTE, nBytes:DWORD, lpWritten:PTR DWORD, lpOverlapped:DWORD
ReadFile             PROTO STDCALL, hFile:DWORD, lpBuffer:PTR BYTE, nBytes:DWORD, lpRead:PTR DWORD, lpOverlapped:DWORD
CloseHandle          PROTO STDCALL, hObject:DWORD
GetLocalTime         PROTO STDCALL, lpTime:PTR WORD
GetCurrentDirectoryA PROTO STDCALL, nLength:DWORD, lpBuffer:PTR BYTE

GENERIC_READ          = 80000000h
GENERIC_WRITE         = 40000000h
FILE_SHARE_READ       = 1
FILE_SHARE_RW         = 3
CREATE_ALWAYS         = 2
OPEN_EXISTING         = 3
OPEN_ALWAYS           = 4
FILE_ATTRIBUTE_NORMAL = 80h
FILE_BEGIN            = 0
FILE_END              = 2
INVALID_HANDLE        = -1

.data
; ---------- graph ----------
gN        DWORD 0
gGraph    DWORD MAXN*MAXN DUP(INF)
gDist     DWORD MAXN DUP(INF)
gPrev     SDWORD MAXN DUP(-1)
gVisited  BYTE  MAXN DUP(0)

; ---------- map positions and named areas ----------
gNodeX    DWORD MAXN DUP(0)          ; junction position on the map picture
gNodeY    DWORD MAXN DUP(0)
gLmCount  DWORD 0
gLmName   DWORD MAXLM DUP(0)         ; pointers to the area names
gLmNode   DWORD MAXLM DUP(0)         ; junction of each area
gLmOfNode SDWORD MAXN DUP(-1)        ; area number of a junction, or -1
gNearLm   SDWORD MAXN DUP(-1)        ; closest area of a junction, or -1

; ---------- favourites ----------
gFavCount DWORD 0
gFavNode  DWORD MAXFAV DUP(0)
gFavType  BYTE  MAXFAV DUP(0)        ; 'H' heart (home) or 'S' star
gFavName  BYTE  MAXFAV*NAMELEN DUP(0)
gFavOfNode SDWORD MAXN DUP(-1)
gFavBuf   BYTE  8192 DUP(0)
gFavOut   BYTE  MAXFAV*100 DUP(0)

; ---------- route ----------
gPath     DWORD MAXN DUP(0)
gPathLen  DWORD 0

; ---------- history ----------
gHistBuf  BYTE  65536 DUP(0)
gHistCount DWORD 0
gRecent   BYTE  3*260 DUP(0)
gRecentN  DWORD 0
gHn       DWORD 0
gStartRing DWORD 3 DUP(0)
gLenRing   DWORD 3 DUP(0)

; ---------- scratch ----------
gDir      BYTE  260 DUP(0)
gHistPath BYTE  300 DUP(0)
gFavPath  BYTE  300 DUP(0)
gLineBuf  BYTE  2000 DUP(0)
gRouteBuf BYTE  1500 DUP(0)
gQ        BYTE  64 DUP(0)
gNm       BYTE  64 DUP(0)
gNm2      BYTE  64 DUP(0)
gNm3      BYTE  96 DUP(0)
gNumBuf   BYTE  16 DUP(0)
gTime     WORD  8 DUP(0)             ; SYSTEMTIME
gCur      DWORD 0
gX        DWORD 0
gY        DWORD 0
gTmpVal   DWORD 0
gTmpPtr   DWORD 0
gTmpPtr2  DWORD 0
gNeedle   DWORD 0
gIdx      DWORD 0
gLineStart DWORD 0
gTypeTmp  DWORD 0
gD        DWORD 0
gTenth    DWORD 0

szHistFile BYTE "\route_history.txt",0
szFavFile  BYTE "\favourites.txt",0
szArrow    BYTE " -> ",0
szNear     BYTE "Near ",0
szJunction BYTE "Road junction",0
szHash     BYTE "#",0
szSpace    BYTE " ",0
szBar      BYTE " | ",0
szDot      BYTE ".",0
szKm       BYTE " km | ",0
szMin      BYTE " min | ",0
szDash     BYTE "-",0
szColon    BYTE ":",0
szSteps    BYTE " steps | route: ",0
szCRLF     BYTE 0Dh,0Ah,0
szMonths   BYTE "Jan",0,"Feb",0,"Mar",0,"Apr",0,"May",0,"Jun",0
           BYTE "Jul",0,"Aug",0,"Sep",0,"Oct",0,"Nov",0,"Dec",0

.code
; ============================================================
; STRING HELPERS
; ============================================================

; length of a null-terminated string
StrLen PROC USES esi, s:PTR BYTE
    mov  esi, s
    mov  eax, 0
SLLoop:
    cmp  BYTE PTR [esi+eax], 0
    je   SLDone
    inc  eax
    jmp  SLLoop
SLDone:
    ret
StrLen ENDP

; copy src to dst (with the 0); returns the address of dst's 0 byte
StrCopy PROC USES esi edi, dst:PTR BYTE, src:PTR BYTE
    mov  esi, src
    mov  edi, dst
SCLoop:
    mov  al, [esi]
    mov  [edi], al
    cmp  al, 0
    je   SCDone
    inc  esi
    inc  edi
    jmp  SCLoop
SCDone:
    mov  eax, edi
    ret
StrCopy ENDP

; append src to the end of dst; returns the new end address
StrCat PROC USES edi, dst:PTR BYTE, src:PTR BYTE
    mov  edi, dst
SKFind:
    cmp  BYTE PTR [edi], 0
    je   SKGo
    inc  edi
    jmp  SKFind
SKGo:
    INVOKE StrCopy, edi, src
    ret
StrCat ENDP

; unsigned number -> decimal text; returns the address of the 0 byte
IntToStr PROC USES ebx ecx edx edi, value:DWORD, dst:PTR BYTE
    mov  eax, value
    mov  ebx, 10
    mov  ecx, 0
ITDiv:
    mov  edx, 0
    div  ebx
    add  dl, '0'
    push edx                      ; keep the digit (last digit first)
    inc  ecx
    cmp  eax, 0
    jne  ITDiv
    mov  edi, dst
ITOut:
    pop  edx
    mov  [edi], dl
    inc  edi
    loop ITOut
    mov  BYTE PTR [edi], 0
    mov  eax, edi
    ret
IntToStr ENDP

; number 0-99 -> two digits ("07"); returns the address of the 0 byte
IntToStr2 PROC USES ebx edx esi, value:DWORD, dst:PTR BYTE
    mov  esi, dst
    mov  eax, value
    mov  edx, 0
    mov  ebx, 10
    div  ebx                      ; AL = tens, DL = ones
    add  al, '0'
    mov  [esi], al
    add  dl, '0'
    mov  [esi+1], dl
    mov  BYTE PTR [esi+2], 0
    lea  eax, [esi+2]
    ret
IntToStr2 ENDP

; append a number / a 2-digit number to a string
CatInt PROC, dst:PTR BYTE, value:DWORD
    INVOKE IntToStr, value, OFFSET gNumBuf
    INVOKE StrCat, dst, OFFSET gNumBuf
    ret
CatInt ENDP

CatInt2 PROC, dst:PTR BYTE, value:DWORD
    INVOKE IntToStr2, value, OFFSET gNumBuf
    INVOKE StrCat, dst, OFFSET gNumBuf
    ret
CatInt2 ENDP

; copy src to dst in lower case (at most maxLen-1 characters)
ToLowerStr PROC USES ecx esi edi, dst:PTR BYTE, src:PTR BYTE, maxLen:DWORD
    mov  esi, src
    mov  edi, dst
    mov  ecx, maxLen
    dec  ecx
TLLoop:
    cmp  ecx, 0
    jle  TLDone
    mov  al, [esi]
    cmp  al, 0
    je   TLDone
    cmp  al, 'A'
    jb   TLStore
    cmp  al, 'Z'
    ja   TLStore
    add  al, 32                   ; 'A' -> 'a'
TLStore:
    mov  [edi], al
    inc  esi
    inc  edi
    dec  ecx
    jmp  TLLoop
TLDone:
    mov  BYTE PTR [edi], 0
    ret
ToLowerStr ENDP

; compare two strings ignoring case: EAX = 0 when equal
StrICmp PROC USES ebx esi edi, a:PTR BYTE, b:PTR BYTE
    mov  esi, a
    mov  edi, b
SILoop:
    mov  al, [esi]
    mov  bl, [edi]
    cmp  al, 'A'
    jb   SIB
    cmp  al, 'Z'
    ja   SIB
    add  al, 32
SIB:
    cmp  bl, 'A'
    jb   SICmp
    cmp  bl, 'Z'
    ja   SICmp
    add  bl, 32
SICmp:
    cmp  al, bl
    jne  SINe
    cmp  al, 0
    je   SIEq
    inc  esi
    inc  edi
    jmp  SILoop
SIEq:
    mov  eax, 0
    ret
SINe:
    mov  eax, 1
    ret
StrICmp ENDP

; EAX = 1 if hay starts with needle
StrPrefix PROC USES ebx esi edi, hay:PTR BYTE, needle:PTR BYTE
    mov  esi, hay
    mov  edi, needle
SPLoop:
    mov  al, [edi]
    cmp  al, 0
    je   SPYes                    ; needle finished: it is a prefix
    mov  bl, [esi]
    cmp  al, bl
    jne  SPNo
    inc  esi
    inc  edi
    jmp  SPLoop
SPYes:
    mov  eax, 1
    ret
SPNo:
    mov  eax, 0
    ret
StrPrefix ENDP

; EAX = 1 if needle occurs anywhere inside hay
StrContains PROC USES ebx esi edi, hay:PTR BYTE, needle:PTR BYTE
    mov  esi, hay
SCStart:
    cmp  BYTE PTR [esi], 0
    je   SCNo
    mov  ebx, esi
    mov  edi, needle
SCCmp:
    mov  al, [edi]
    cmp  al, 0
    je   SCYes
    cmp  al, [ebx]
    jne  SCNext
    inc  ebx
    inc  edi
    jmp  SCCmp
SCNext:
    inc  esi
    jmp  SCStart
SCYes:
    mov  eax, 1
    ret
SCNo:
    mov  eax, 0
    ret
StrContains ENDP

; reads a decimal number at [gCur] and moves gCur past it
ReadNum PROC USES ebx esi
    mov  esi, gCur
    mov  eax, 0
RNLoop:
    movzx ebx, BYTE PTR [esi]
    cmp  ebx, '0'
    jb   RNDone
    cmp  ebx, '9'
    ja   RNDone
    imul eax, 10
    sub  ebx, '0'
    add  eax, ebx
    inc  esi
    jmp  RNLoop
RNDone:
    mov  gCur, esi
    ret
ReadNum ENDP

; EAX = v mod 3
Mod3 PROC USES ebx edx, v:DWORD
    mov  eax, v
    mov  edx, 0
    mov  ebx, 3
    div  ebx
    mov  eax, edx
    ret
Mod3 ENDP

; ============================================================
; GRAPH AND DIJKSTRA
; ============================================================

; void GraphReset(int cnt) : n = cnt, remove every road
GraphReset PROC USES esi, cnt:DWORD
    mov  eax, cnt
    mov  gN, eax
    mov  esi, 0
GRLoop:
    cmp  esi, MAXN*MAXN
    jge  GRDone
    mov  gGraph[esi*4], INF
    inc  esi
    jmp  GRLoop
GRDone:
    ret
GraphReset ENDP

; void GraphAddEdge(int nu, int nv, int nw) : undirected road
GraphAddEdge PROC USES ebx esi, nu:DWORD, nv:DWORD, nw:DWORD
    mov  ebx, nw
    mov  esi, nu
    imul esi, MAXN
    add  esi, nv
    mov  gGraph[esi*4], ebx
    mov  esi, nv
    imul esi, MAXN
    add  esi, nu
    mov  gGraph[esi*4], ebx
    ret
GraphAddEdge ENDP

; void DijkstraInit(int srcNode)
DijkstraInit PROC USES esi, srcNode:DWORD
    mov  esi, 0
DILoop:
    cmp  esi, MAXN
    jge  DIDone
    mov  gDist[esi*4], INF
    mov  gPrev[esi*4], -1
    mov  gVisited[esi], 0
    inc  esi
    jmp  DILoop
DIDone:
    mov  esi, srcNode
    mov  gDist[esi*4], 0
    ret
DijkstraInit ENDP

; int DijkstraStep() : ONE iteration; returns the junction finalised, or -1
DijkstraStep PROC USES ebx ecx edx esi edi
    mov  ebx, -1                  ; best junction
    mov  ecx, INF                 ; best distance
    mov  esi, 0
DSFind:
    cmp  esi, gN
    jge  DSFound
    cmp  gVisited[esi], 0
    jne  DSFNext
    mov  eax, gDist[esi*4]
    cmp  eax, ecx
    jge  DSFNext
    mov  ebx, esi
    mov  ecx, eax
DSFNext:
    inc  esi
    jmp  DSFind
DSFound:
    cmp  ebx, -1
    je   DSExit
    mov  gVisited[ebx], 1
    mov  edi, 0
DSRelax:
    cmp  edi, gN
    jge  DSExit
    cmp  gVisited[edi], 0
    jne  DSRNext
    mov  eax, ebx
    imul eax, MAXN
    add  eax, edi
    mov  edx, gGraph[eax*4]
    cmp  edx, INF
    je   DSRNext
    mov  eax, gDist[ebx*4]
    add  eax, edx
    cmp  eax, gDist[edi*4]
    jge  DSRNext
    mov  gDist[edi*4], eax
    mov  gPrev[edi*4], ebx
DSRNext:
    inc  edi
    jmp  DSRelax
DSExit:
    mov  eax, ebx
    ret
DijkstraStep ENDP

GetDist PROC, idx:DWORD
    mov  eax, idx
    mov  eax, gDist[eax*4]
    ret
GetDist ENDP

GetPrev PROC, idx:DWORD
    mov  eax, idx
    mov  eax, gPrev[eax*4]
    ret
GetPrev ENDP

GetVisited PROC, idx:DWORD
    mov  eax, idx
    movzx eax, gVisited[eax]
    ret
GetVisited ENDP

; ============================================================
; FILE HANDLING (Windows API called from assembly)
; ============================================================

; int AppendToFile(const char* fname, const char* text) : 1 = ok
AppendToFile PROC USES ebx esi, fname:PTR BYTE, text:PTR BYTE
    LOCAL hFile:DWORD, written:DWORD
    INVOKE CreateFileA, fname, GENERIC_WRITE, FILE_SHARE_READ, 0, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    cmp  eax, INVALID_HANDLE
    je   AFFail
    mov  hFile, eax
    INVOKE SetFilePointer, hFile, 0, 0, FILE_END
    mov  esi, text
    mov  ebx, 0
AFLen:
    cmp  BYTE PTR [esi+ebx], 0
    je   AFLenDone
    inc  ebx
    jmp  AFLen
AFLenDone:
    INVOKE WriteFile, hFile, text, ebx, ADDR written, 0
    INVOKE CloseHandle, hFile
    mov  eax, 1
    ret
AFFail:
    mov  eax, 0
    ret
AppendToFile ENDP

; int ReadWholeFile(const char* fname, char* buf, int bufSize)
;   reads the file (its LAST bufSize-1 bytes if it is bigger);
;   returns the bytes read, 0 if the file is missing
ReadWholeFile PROC USES ebx, fname:PTR BYTE, buf:PTR BYTE, bufSize:DWORD
    LOCAL hFile:DWORD, got:DWORD
    mov  got, 0
    INVOKE CreateFileA, fname, GENERIC_READ, FILE_SHARE_RW, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
    cmp  eax, INVALID_HANDLE
    je   RFEnd
    mov  hFile, eax
    mov  ebx, bufSize
    dec  ebx
    INVOKE GetFileSize, hFile, 0
    cmp  eax, ebx
    jbe  RFRead
    sub  eax, ebx
    INVOKE SetFilePointer, hFile, eax, 0, FILE_BEGIN
RFRead:
    INVOKE ReadFile, hFile, buf, ebx, ADDR got, 0
    INVOKE CloseHandle, hFile
RFEnd:
    mov  ebx, buf
    mov  eax, got
    mov  BYTE PTR [ebx+eax], 0
    ret
ReadWholeFile ENDP

; int ClearFile(const char* fname) : empties the file
ClearFile PROC, fname:PTR BYTE
    LOCAL hFile:DWORD
    INVOKE CreateFileA, fname, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    cmp  eax, INVALID_HANDLE
    je   CFFail
    mov  hFile, eax
    INVOKE CloseHandle, hFile
    mov  eax, 1
    ret
CFFail:
    mov  eax, 0
    ret
ClearFile ENDP

; int CountLines(const char* text) : number of line feeds
CountLines PROC USES esi, text:PTR BYTE
    mov  esi, text
    mov  eax, 0
CLLoop:
    cmp  BYTE PTR [esi], 0
    je   CLDone
    cmp  BYTE PTR [esi], 0Ah
    jne  CLNext
    inc  eax
CLNext:
    inc  esi
    jmp  CLLoop
CLDone:
    ret
CountLines ENDP

; ============================================================
; MAP DATA: junction positions and named areas
; ============================================================

SetNodePos PROC USES esi, idx:DWORD, nx:DWORD, ny:DWORD
    mov  esi, idx
    mov  eax, nx
    mov  gNodeX[esi*4], eax
    mov  eax, ny
    mov  gNodeY[esi*4], eax
    ret
SetNodePos ENDP

AddLandmark PROC USES esi, namePtr:PTR BYTE, node:DWORD
    mov  esi, gLmCount
    mov  eax, namePtr
    mov  gLmName[esi*4], eax
    mov  eax, node
    mov  gLmNode[esi*4], eax
    inc  gLmCount
    ret
AddLandmark ENDP

; after all nodes and areas are set: area-of-junction tables
MapFinish PROC USES ebx ecx edx esi edi
    mov  esi, 0
MFClear:
    cmp  esi, MAXN
    jge  MFMark
    mov  gLmOfNode[esi*4], -1
    mov  gNearLm[esi*4], -1
    mov  gFavOfNode[esi*4], -1
    inc  esi
    jmp  MFClear
MFMark:
    mov  esi, 0
MFMark2:
    cmp  esi, gLmCount
    jge  MFNear
    mov  eax, gLmNode[esi*4]
    mov  gLmOfNode[eax*4], esi
    inc  esi
    jmp  MFMark2
MFNear:
    mov  edi, 0                   ; junction
MFNode:
    cmp  edi, gN
    jge  MFDone
    cmp  gLmOfNode[edi*4], -1
    je   MFCalc
    mov  eax, gLmOfNode[edi*4]    ; an area's own junction
    mov  gNearLm[edi*4], eax
    jmp  MFNext
MFCalc:
    mov  ebx, 6400                ; closest area within 80 map pixels
    mov  esi, 0
MFArea:
    cmp  esi, gLmCount
    jge  MFNext
    mov  ecx, gLmNode[esi*4]
    mov  eax, gNodeX[edi*4]
    sub  eax, gNodeX[ecx*4]
    imul eax, eax
    mov  edx, gNodeY[edi*4]
    sub  edx, gNodeY[ecx*4]
    imul edx, edx
    add  eax, edx
    cmp  eax, ebx
    jge  MFAreaNext
    mov  ebx, eax
    mov  gNearLm[edi*4], esi
MFAreaNext:
    inc  esi
    jmp  MFArea
MFNext:
    inc  edi
    jmp  MFNode
MFDone:
    ret
MapFinish ENDP

; junction position on the screen: (map pixel * 960 + 635) / 1270
NodeSX PROC USES ebx edx, idx:DWORD
    mov  eax, idx
    mov  eax, gNodeX[eax*4]
    imul eax, 960
    add  eax, 635
    mov  edx, 0
    mov  ebx, 1270
    div  ebx
    ret
NodeSX ENDP

NodeSY PROC USES ebx edx, idx:DWORD
    mov  eax, idx
    mov  eax, gNodeY[eax*4]
    imul eax, 960
    add  eax, 635
    mov  edx, 0
    mov  ebx, 1270
    div  ebx
    ret
NodeSY ENDP

; area number whose dot is within radius2 (squared pixels) of (sx, sy), or -1
HitLandmark PROC USES ebx ecx edx esi, sx:DWORD, sy:DWORD, radius2:DWORD
    mov  esi, 0
HLLoop:
    cmp  esi, gLmCount
    jge  HLNone
    mov  ecx, gLmNode[esi*4]
    INVOKE NodeSX, ecx
    sub  eax, sx
    imul eax, eax
    mov  ebx, eax
    INVOKE NodeSY, ecx
    sub  eax, sy
    imul eax, eax
    add  eax, ebx
    cmp  eax, radius2
    jg   HLNext
    mov  eax, esi
    ret
HLNext:
    inc  esi
    jmp  HLLoop
HLNone:
    mov  eax, -1
    ret
HitLandmark ENDP

; junction for a mouse click: an area dot first, else the nearest junction
HitNode PROC USES ebx ecx edx esi edi, sx:DWORD, sy:DWORD
    INVOKE HitLandmark, sx, sy, 225
    cmp  eax, -1
    je   HNJunction
    mov  eax, gLmNode[eax*4]
    ret
HNJunction:
    mov  edi, -1
    mov  ebx, 325                 ; within 18 pixels
    mov  esi, 0
HNLoop:
    cmp  esi, gN
    jge  HNDone
    INVOKE NodeSX, esi
    sub  eax, sx
    imul eax, eax
    mov  ecx, eax
    INVOKE NodeSY, esi
    sub  eax, sy
    imul eax, eax
    add  eax, ecx
    cmp  eax, ebx
    jge  HNNext
    mov  ebx, eax
    mov  edi, esi
HNNext:
    inc  esi
    jmp  HNLoop
HNDone:
    mov  eax, edi
    ret
HitNode ENDP

; ============================================================
; NAMES AND PLACES
; ============================================================

; writes the name of a junction into dst: favourite name, area name,
; "Near <area>" or "Road junction"
NodeName PROC USES esi edi, node:DWORD, dst:PTR BYTE
    mov  esi, node
    mov  eax, gFavOfNode[esi*4]
    cmp  eax, -1
    je   NNArea
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    INVOKE StrCopy, dst, eax
    ret
NNArea:
    mov  eax, gLmOfNode[esi*4]
    cmp  eax, -1
    je   NNNear
    mov  edi, gLmName[eax*4]
    INVOKE StrCopy, dst, edi
    ret
NNNear:
    mov  eax, gNearLm[esi*4]
    cmp  eax, -1
    je   NNJunction
    mov  edi, gLmName[eax*4]
    INVOKE StrCopy, dst, OFFSET szNear
    INVOKE StrCat, dst, edi
    ret
NNJunction:
    INVOKE StrCopy, dst, OFFSET szJunction
    ret
NodeName ENDP

; all places = the named areas followed by the favourites
PlaceCount PROC
    mov  eax, gLmCount
    add  eax, gFavCount
    ret
PlaceCount ENDP

PlaceNameAt PROC, i:DWORD
    mov  eax, i
    cmp  eax, gLmCount
    jge  PNFav
    mov  eax, gLmName[eax*4]
    ret
PNFav:
    sub  eax, gLmCount
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    ret
PlaceNameAt ENDP

PlaceNodeAt PROC, i:DWORD
    mov  eax, i
    cmp  eax, gLmCount
    jge  PNdFav
    mov  eax, gLmNode[eax*4]
    ret
PNdFav:
    sub  eax, gLmCount
    mov  eax, gFavNode[eax*4]
    ret
PlaceNodeAt ENDP

; typed text -> place number, or -1.
; Passes: exact match, starts-with, contains (case-insensitive).
; Favourites are checked before the built-in areas.
FindPlace PROC USES ebx ecx edx esi edi, text:PTR BYTE
    INVOKE ToLowerStr, OFFSET gQ, text, 64
    INVOKE StrLen, OFFSET gQ
    mov  ecx, eax
FPTrim:                           ; cut trailing spaces
    cmp  ecx, 0
    jle  FPTrimDone
    cmp  gQ[ecx-1], ' '
    jne  FPTrimDone
    dec  ecx
    mov  gQ[ecx], 0
    jmp  FPTrim
FPTrimDone:
    mov  esi, OFFSET gQ           ; skip leading spaces
FPSkip:
    cmp  BYTE PTR [esi], ' '
    jne  FPSkipDone
    inc  esi
    jmp  FPSkip
FPSkipDone:
    cmp  BYTE PTR [esi], 0
    je   FPNone
    mov  gNeedle, esi
    mov  ebx, 0                   ; pass number
FPPass:
    cmp  ebx, 3
    jge  FPNone
    mov  edi, 0                   ; position in the search order
FPItem:
    INVOKE PlaceCount
    cmp  edi, eax
    jge  FPNextPass
    mov  ecx, edi
    cmp  edi, gFavCount
    jl   FPFavFirst
    sub  ecx, gFavCount           ; built-in area number
    jmp  FPHave
FPFavFirst:
    add  ecx, gLmCount            ; favourite, numbered after the areas
FPHave:
    mov  gIdx, ecx
    INVOKE PlaceNameAt, ecx
    mov  gTmpPtr, eax
    INVOKE ToLowerStr, OFFSET gNm, gTmpPtr, 64
    cmp  ebx, 0
    jne  FPPass1
    INVOKE StrICmp, OFFSET gNm, gNeedle
    cmp  eax, 0
    je   FPFound
    jmp  FPNextItem
FPPass1:
    cmp  ebx, 1
    jne  FPPass2
    INVOKE StrPrefix, OFFSET gNm, gNeedle
    cmp  eax, 1
    je   FPFound
    jmp  FPNextItem
FPPass2:
    INVOKE StrContains, OFFSET gNm, gNeedle
    cmp  eax, 1
    je   FPFound
FPNextItem:
    inc  edi
    jmp  FPItem
FPNextPass:
    inc  ebx
    jmp  FPPass
FPFound:
    mov  eax, gIdx
    ret
FPNone:
    mov  eax, -1
    ret
FindPlace ENDP

; ============================================================
; FAVOURITES  (favourites.txt, one line each:  x|y|H|name)
; ============================================================

RebuildFavIndex PROC USES ecx esi
    mov  esi, 0
RFClear:
    cmp  esi, MAXN
    jge  RFFill
    mov  gFavOfNode[esi*4], -1
    inc  esi
    jmp  RFClear
RFFill:
    mov  esi, 0
RFLoop:
    cmp  esi, gFavCount
    jge  RFDone
    mov  ecx, gFavNode[esi*4]
    mov  gFavOfNode[ecx*4], esi
    inc  esi
    jmp  RFLoop
RFDone:
    ret
RebuildFavIndex ENDP

; writes all favourites to favourites.txt
FavSaveFile PROC USES ebx ecx edx esi edi
    mov  edi, OFFSET gFavOut
    mov  BYTE PTR [edi], 0
    mov  esi, 0
FSLoop:
    cmp  esi, gFavCount
    jge  FSWrite
    mov  ecx, gFavNode[esi*4]
    mov  eax, gNodeX[ecx*4]
    mov  gTmpVal, eax
    INVOKE IntToStr, gTmpVal, edi
    mov  edi, eax
    mov  BYTE PTR [edi], '|'
    inc  edi
    mov  eax, gNodeY[ecx*4]
    mov  gTmpVal, eax
    INVOKE IntToStr, gTmpVal, edi
    mov  edi, eax
    mov  BYTE PTR [edi], '|'
    inc  edi
    mov  al, gFavType[esi]
    mov  [edi], al
    inc  edi
    mov  BYTE PTR [edi], '|'
    inc  edi
    mov  eax, esi
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    mov  gTmpPtr, eax
    INVOKE StrCopy, edi, gTmpPtr
    mov  edi, eax
    mov  BYTE PTR [edi], 0Dh
    inc  edi
    mov  BYTE PTR [edi], 0Ah
    inc  edi
    mov  BYTE PTR [edi], 0
    inc  esi
    jmp  FSLoop
FSWrite:
    INVOKE ClearFile, OFFSET gFavPath
    cmp  BYTE PTR gFavOut, 0
    je   FSEnd
    INVOKE AppendToFile, OFFSET gFavPath, OFFSET gFavOut
FSEnd:
    ret
FavSaveFile ENDP

; reads favourites.txt. Line formats:  x|y|H|name   (new)   x|y|name   (old, heart)
; x, y = position on the map picture; snapped to the nearest junction.
FavLoad PROC USES ebx ecx edx esi edi
    mov  gFavCount, 0
    INVOKE ReadWholeFile, OFFSET gFavPath, OFFSET gFavBuf, 8192
    cmp  eax, 0
    jle  FLEnd
    mov  esi, OFFSET gFavBuf
FLLine:
    cmp  BYTE PTR [esi], 0
    je   FLEnd
    cmp  gFavCount, MAXFAV
    jge  FLEnd
    mov  gLineStart, esi
    mov  gCur, esi
    call ReadNum                  ; x
    mov  gX, eax
    mov  esi, gCur
    cmp  BYTE PTR [esi], '|'
    jne  FLNext
    inc  esi
    mov  gCur, esi
    call ReadNum                  ; y
    mov  gY, eax
    mov  esi, gCur
    cmp  BYTE PTR [esi], '|'
    jne  FLNext
    inc  esi
    mov  gTypeTmp, 'H'            ; old lines have no type: heart
    mov  al, [esi]
    cmp  al, 'H'
    je   FLTypeChk
    cmp  al, 'S'
    jne  FLName
FLTypeChk:
    cmp  BYTE PTR [esi+1], '|'
    jne  FLName
    movzx eax, al
    mov  gTypeTmp, eax
    add  esi, 2
FLName:                           ; copy the name (at most 47 characters)
    mov  edi, OFFSET gNm
    mov  ecx, 0
FLCopy:
    mov  al, [esi]
    cmp  al, 0Dh
    je   FLCopyDone
    cmp  al, 0Ah
    je   FLCopyDone
    cmp  al, 0
    je   FLCopyDone
    cmp  ecx, 47
    jge  FLSkipChar
    mov  [edi], al
    inc  edi
    inc  ecx
FLSkipChar:
    inc  esi
    jmp  FLCopy
FLCopyDone:
    mov  BYTE PTR [edi], 0
    cmp  ecx, 0
    je   FLNext                   ; empty name: ignore the line
    mov  edi, -1                  ; nearest junction within 60 pixels
    mov  ebx, 3600
    mov  esi, 0
FLSnap:
    cmp  esi, gN
    jge  FLSnapDone
    mov  eax, gNodeX[esi*4]
    sub  eax, gX
    imul eax, eax
    mov  ecx, gNodeY[esi*4]
    sub  ecx, gY
    imul ecx, ecx
    add  eax, ecx
    cmp  eax, ebx
    jge  FLSnapNext
    mov  ebx, eax
    mov  edi, esi
FLSnapNext:
    inc  esi
    jmp  FLSnap
FLSnapDone:
    cmp  edi, -1
    je   FLNext
    mov  ecx, gFavCount
    mov  gFavNode[ecx*4], edi
    mov  eax, gTypeTmp
    mov  gFavType[ecx], al
    mov  eax, ecx
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    mov  gTmpPtr, eax
    INVOKE StrCopy, gTmpPtr, OFFSET gNm
    inc  gFavCount
FLNext:                           ; continue after the next line feed
    mov  esi, gLineStart
FLFindEnd:
    cmp  BYTE PTR [esi], 0
    je   FLEnd
    cmp  BYTE PTR [esi], 0Ah
    je   FLAfter
    inc  esi
    jmp  FLFindEnd
FLAfter:
    inc  esi
    jmp  FLLine
FLEnd:
    INVOKE RebuildFavIndex
    ret
FavLoad ENDP

; Adds (favIdx = -1) or changes (favIdx >= 0) a favourite and saves the file.
; ftype is 'H' or 'S'.  Returns 0 = ok, 1 = empty name, 2 = name already
; used by another favourite, 3 = name of a built-in area, 4 = list full.
FavSet PROC USES ebx ecx edx esi edi, favIdx:SDWORD, node:DWORD, ftype:DWORD, namePtr:PTR BYTE
    mov  esi, namePtr             ; clean the name into gNm2
FSSpace:
    cmp  BYTE PTR [esi], ' '
    jne  FSSpaceDone
    inc  esi
    jmp  FSSpace
FSSpaceDone:
    mov  edi, OFFSET gNm2
    mov  ecx, 0
FSCopy:
    mov  al, [esi]
    cmp  al, 0
    je   FSCopyDone
    cmp  ecx, 40
    jge  FSCopyDone
    cmp  al, '|'
    jne  FSPut
    mov  al, ' '                  ; '|' separates the fields in the file
FSPut:
    mov  [edi], al
    inc  esi
    inc  edi
    inc  ecx
    jmp  FSCopy
FSCopyDone:
FSTrim:
    cmp  ecx, 0
    jle  FSTrimDone
    cmp  gNm2[ecx-1], ' '
    jne  FSTrimDone
    dec  ecx
    jmp  FSTrim
FSTrimDone:
    mov  gNm2[ecx], 0
    cmp  ecx, 0
    jne  FSDupFav
    mov  eax, 1
    ret
FSDupFav:
    mov  esi, 0
FSDup1:
    cmp  esi, gFavCount
    jge  FSDupLm
    cmp  esi, favIdx
    je   FSDup1Next
    mov  eax, esi
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    mov  gTmpPtr, eax
    INVOKE StrICmp, gTmpPtr, OFFSET gNm2
    cmp  eax, 0
    jne  FSDup1Next
    mov  eax, 2
    ret
FSDup1Next:
    inc  esi
    jmp  FSDup1
FSDupLm:
    mov  esi, 0
FSDup2:
    cmp  esi, gLmCount
    jge  FSStoreInit
    mov  eax, gLmName[esi*4]
    mov  gTmpPtr, eax
    INVOKE StrICmp, gTmpPtr, OFFSET gNm2
    cmp  eax, 0
    jne  FSDup2Next
    mov  eax, 3
    ret
FSDup2Next:
    inc  esi
    jmp  FSDup2
FSStoreInit:
    cmp  favIdx, 0
    jl   FSNew
    mov  ecx, favIdx
    jmp  FSStore
FSNew:
    cmp  gFavCount, MAXFAV
    jl   FSAdd
    mov  eax, 4
    ret
FSAdd:
    mov  ecx, gFavCount
    inc  gFavCount
FSStore:
    mov  eax, node
    mov  gFavNode[ecx*4], eax
    mov  eax, ftype
    mov  gFavType[ecx], al
    mov  eax, ecx
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    mov  gTmpPtr, eax
    INVOKE StrCopy, gTmpPtr, OFFSET gNm2
    INVOKE RebuildFavIndex
    INVOKE FavSaveFile
    mov  eax, 0
    ret
FavSet ENDP

; removes favourite number idx and saves the file; returns 0 = ok, 1 = bad number
FavDelete PROC USES ebx, idx:DWORD
    mov  ebx, idx
    cmp  ebx, gFavCount
    jb   FDShift
    mov  eax, 1
    ret
FDShift:
    mov  eax, gFavCount
    dec  eax
    cmp  ebx, eax
    jge  FDDone
    mov  eax, gFavNode[ebx*4+4]   ; move the next favourite down
    mov  gFavNode[ebx*4], eax
    mov  al, gFavType[ebx+1]
    mov  gFavType[ebx], al
    mov  eax, ebx
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    mov  gTmpPtr, eax
    add  eax, NAMELEN
    mov  gTmpPtr2, eax
    INVOKE StrCopy, gTmpPtr, gTmpPtr2
    inc  ebx
    jmp  FDShift
FDDone:
    dec  gFavCount
    INVOKE RebuildFavIndex
    INVOKE FavSaveFile
    mov  eax, 0
    ret
FavDelete ENDP

FavCount PROC
    mov  eax, gFavCount
    ret
FavCount ENDP

FavNodeAt PROC, i:DWORD
    mov  eax, i
    mov  eax, gFavNode[eax*4]
    ret
FavNodeAt ENDP

FavTypeAt PROC, i:DWORD
    mov  eax, i
    movzx eax, gFavType[eax]
    ret
FavTypeAt ENDP

FavNameAt PROC, i:DWORD
    mov  eax, i
    imul eax, NAMELEN
    add  eax, OFFSET gFavName
    ret
FavNameAt ENDP

FavOfNodeAt PROC, node:DWORD
    mov  eax, node
    mov  eax, gFavOfNode[eax*4]
    ret
FavOfNodeAt ENDP

; ============================================================
; ROUTE
; ============================================================

; rebuilds the route source -> dstNode from prev[]; returns its length
BuildPath PROC USES ebx ecx edx esi edi, dstNode:DWORD
    mov  ecx, 0
    mov  esi, dstNode
BPTrace:
    cmp  esi, -1
    je   BPTraced
    cmp  ecx, MAXN
    jge  BPTraced
    mov  gPath[ecx*4], esi
    inc  ecx
    mov  esi, gPrev[esi*4]
    jmp  BPTrace
BPTraced:
    mov  gPathLen, ecx
    mov  esi, 0                   ; reverse: destination-first -> source-first
    mov  edi, ecx
    dec  edi
BPRev:
    cmp  esi, edi
    jge  BPDone
    mov  eax, gPath[esi*4]
    mov  edx, gPath[edi*4]
    mov  gPath[esi*4], edx
    mov  gPath[edi*4], eax
    inc  esi
    dec  edi
    jmp  BPRev
BPDone:
    mov  eax, gPathLen
    ret
BuildPath ENDP

GetPathLen PROC
    mov  eax, gPathLen
    ret
GetPathLen ENDP

GetPathNode PROC, i:DWORD
    mov  eax, i
    mov  eax, gPath[eax*4]
    ret
GetPathNode ENDP

; "Start -> area -> area -> End" for the current route: both ends,
; and the named areas / favourites in between
RouteString PROC USES ebx esi edi, dstBuf:PTR BYTE
    mov  edi, dstBuf
    mov  BYTE PTR [edi], 0
    mov  esi, 0
RSLoop:
    cmp  esi, gPathLen
    jge  RSDone
    mov  ebx, gPath[esi*4]
    cmp  esi, 0
    je   RSUse
    mov  eax, gPathLen
    dec  eax
    cmp  esi, eax
    je   RSUse
    cmp  gLmOfNode[ebx*4], -1
    jne  RSUse
    cmp  gFavOfNode[ebx*4], -1
    je   RSNext
RSUse:
    INVOKE NodeName, ebx, OFFSET gNm3
    cmp  BYTE PTR [edi], 0
    je   RSName
    INVOKE StrCat, edi, OFFSET szArrow
RSName:
    INVOKE StrCat, edi, OFFSET gNm3
RSNext:
    inc  esi
    jmp  RSLoop
RSDone:
    ret
RouteString ENDP

; ============================================================
; ROUTE HISTORY  (route_history.txt, one line per route)
; ============================================================

; reads the file; keeps the number of records and the 3 newest lines
HistLoad PROC USES ebx ecx esi edi
    INVOKE ReadWholeFile, OFFSET gHistPath, OFFSET gHistBuf, 65536
    INVOKE CountLines, OFFSET gHistBuf
    mov  gHistCount, eax
    mov  gHn, 0
    mov  esi, OFFSET gHistBuf
HLScan:
    cmp  BYTE PTR [esi], 0
    je   HLCopy
    mov  edi, esi                 ; start of the line
    mov  ebx, esi
HLFind:
    mov  al, [ebx]
    cmp  al, 0
    je   HLFound
    cmp  al, 0Ah
    je   HLFound
    inc  ebx
    jmp  HLFind
HLFound:
    mov  ecx, ebx
    sub  ecx, edi                 ; ECX = line length
    cmp  ecx, 0
    jle  HLNextLine
    cmp  BYTE PTR [edi+ecx-1], 0Dh
    jne  HLKeep
    dec  ecx                      ; drop the CR
HLKeep:
    cmp  ecx, 0
    jle  HLNextLine
    INVOKE Mod3, gHn              ; ring of the last 3 lines
    mov  gStartRing[eax*4], edi
    mov  gLenRing[eax*4], ecx
    inc  gHn
HLNextLine:
    mov  esi, ebx
    cmp  BYTE PTR [esi], 0
    je   HLCopy
    inc  esi
    jmp  HLScan
HLCopy:
    mov  eax, gHn
    cmp  eax, 3
    jle  HLSet
    mov  eax, 3
HLSet:
    mov  gRecentN, eax
    mov  ebx, 0                   ; k = 0 is the newest
HLOne:
    cmp  ebx, gRecentN
    jge  HLEnd
    mov  eax, gHn
    dec  eax
    sub  eax, ebx
    mov  gTmpVal, eax
    INVOKE Mod3, gTmpVal
    mov  esi, gStartRing[eax*4]
    mov  ecx, gLenRing[eax*4]
    cmp  ecx, 259
    jle  HLLen
    mov  ecx, 259
HLLen:
    mov  eax, ebx
    imul eax, 260
    lea  edi, gRecent[eax]
HLByte:
    cmp  ecx, 0
    jle  HLByteDone
    mov  al, [esi]
    mov  [edi], al
    inc  esi
    inc  edi
    dec  ecx
    jmp  HLByte
HLByteDone:
    mov  BYTE PTR [edi], 0
    inc  ebx
    jmp  HLOne
HLEnd:
    ret
HistLoad ENDP

; Adds one line for the finished route (source -> destination):
; #n  Start -> End | km | minutes | date time | steps | route: ...
; Returns 1 if the line was written.
HistAppend PROC USES ebx ecx edx esi edi, srcNode:DWORD, dstNode:DWORD, steps:DWORD
    mov  gLineBuf, 0
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szHash
    mov  eax, gHistCount
    inc  eax
    mov  gTmpVal, eax
    INVOKE CatInt, OFFSET gLineBuf, gTmpVal
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szSpace
    INVOKE NodeName, srcNode, OFFSET gNm3
    INVOKE StrCat, OFFSET gLineBuf, OFFSET gNm3
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szArrow
    INVOKE NodeName, dstNode, OFFSET gNm3
    INVOKE StrCat, OFFSET gLineBuf, OFFSET gNm3
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szBar

    mov  ebx, dstNode             ; distance: km.tenth and minutes
    mov  eax, gDist[ebx*4]
    mov  gD, eax
    mov  edx, 0
    mov  ecx, 10
    div  ecx
    mov  gTenth, edx
    mov  gTmpVal, eax
    INVOKE CatInt, OFFSET gLineBuf, gTmpVal
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szDot
    INVOKE CatInt, OFFSET gLineBuf, gTenth
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szKm
    mov  eax, gD
    mov  edx, 0
    mov  ecx, 5                   ; 30 km/h = 5 tenths of a km per minute
    div  ecx
    mov  gTmpVal, eax
    INVOKE CatInt, OFFSET gLineBuf, gTmpVal
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szMin

    INVOKE GetLocalTime, OFFSET gTime          ; date and time
    movzx eax, WORD PTR gTime+6
    mov  gTmpVal, eax
    INVOKE CatInt2, OFFSET gLineBuf, gTmpVal   ; day
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szDash
    movzx eax, WORD PTR gTime+2
    dec  eax
    shl  eax, 2                                ; 4 bytes per month name
    add  eax, OFFSET szMonths
    mov  gTmpPtr, eax
    INVOKE StrCat, OFFSET gLineBuf, gTmpPtr
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szDash
    movzx eax, WORD PTR gTime
    mov  gTmpVal, eax
    INVOKE CatInt, OFFSET gLineBuf, gTmpVal    ; year
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szSpace
    movzx eax, WORD PTR gTime+8
    mov  gTmpVal, eax
    INVOKE CatInt2, OFFSET gLineBuf, gTmpVal   ; hour
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szColon
    movzx eax, WORD PTR gTime+10
    mov  gTmpVal, eax
    INVOKE CatInt2, OFFSET gLineBuf, gTmpVal   ; minute
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szColon
    movzx eax, WORD PTR gTime+12
    mov  gTmpVal, eax
    INVOKE CatInt2, OFFSET gLineBuf, gTmpVal   ; second

    INVOKE StrCat, OFFSET gLineBuf, OFFSET szBar
    INVOKE CatInt, OFFSET gLineBuf, steps
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szSteps
    INVOKE RouteString, OFFSET gRouteBuf
    INVOKE StrCat, OFFSET gLineBuf, OFFSET gRouteBuf
    INVOKE StrCat, OFFSET gLineBuf, OFFSET szCRLF

    INVOKE AppendToFile, OFFSET gHistPath, OFFSET gLineBuf
    mov  esi, eax
    INVOKE HistLoad
    mov  eax, esi
    ret
HistAppend ENDP

; empties route_history.txt
ClearHistory PROC
    INVOKE ClearFile, OFFSET gHistPath
    INVOKE HistLoad
    ret
ClearHistory ENDP

HistCount PROC
    mov  eax, gHistCount
    ret
HistCount ENDP

HistRecentN PROC
    mov  eax, gRecentN
    ret
HistRecentN ENDP

HistRecentAt PROC, k:DWORD
    mov  eax, k
    imul eax, 260
    add  eax, OFFSET gRecent
    ret
HistRecentAt ENDP

; ============================================================
; START-UP
; ============================================================

; file names = current folder + name
FilesInit PROC
    mov  gDir, 0
    INVOKE GetCurrentDirectoryA, 260, OFFSET gDir
    INVOKE StrCopy, OFFSET gHistPath, OFFSET gDir
    INVOKE StrCat, OFFSET gHistPath, OFFSET szHistFile
    INVOKE StrCopy, OFFSET gFavPath, OFFSET gDir
    INVOKE StrCat, OFFSET gFavPath, OFFSET szFavFile
    ret
FilesInit ENDP

GetHistPath PROC
    mov  eax, OFFSET gHistPath
    ret
GetHistPath ENDP

GetFavPath PROC
    mov  eax, OFFSET gFavPath
    ret
GetFavPath ENDP

; removes every favourite and empties favourites.txt; returns 0
FavClearAll PROC
    mov  gFavCount, 0
    INVOKE RebuildFavIndex
    INVOKE FavSaveFile
    mov  eax, 0
    ret
FavClearAll ENDP

; call once after GraphReset / SetNodePos / AddLandmark / GraphAddEdge
DataInit PROC
    INVOKE FilesInit
    INVOKE MapFinish
    INVOKE FavLoad
    INVOKE HistLoad
    ret
DataInit ENDP

END
