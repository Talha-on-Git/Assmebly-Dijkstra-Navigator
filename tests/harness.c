// Test harness: runs the REAL assembly module (Linux build, Windows API replaced by small stubs)
__asm__(".globl _start\n_start:\n call main\n mov %eax,%ebx\n mov $1,%eax\n int $0x80\n");
#include "MapData_c.h"
static int sys3(int n,int a,int b,int c){int r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static int slen(const char*s){int n=0;while(s[n])n++;return n;}
static void puts_(const char*s){sys3(4,1,(int)s,slen(s));}
static void putn(int v){char b[16];int i=15;b[i]=0;int neg=v<0;unsigned u=neg?(unsigned)(-v):(unsigned)v;if(!u)b[--i]='0';while(u){b[--i]='0'+u%10;u/=10;}if(neg)b[--i]='-';puts_(b+i);}
static int seq(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static int startsw(const char*a,const char*p){while(*p){if(*a!=*p)return 0;a++;p++;}return 1;}
static int has(const char*h,const char*n){int ln=slen(n);for(;*h;h++)if(startsw(h,n)&&ln)return 1;return 0;}
static int fails=0,passes=0;
static void check(const char*w,int ok){if(ok){passes++;}else{fails++;puts_("FAIL: ");puts_(w);puts_("\n");}}

// ---- Windows API stand-ins (cdecl, built with the API declared as C instead of STDCALL) ----
int CreateFileA(const char*p,unsigned acc,unsigned sh,unsigned sec,unsigned cr,unsigned at,unsigned t) __asm__("_CreateFileA");
int CreateFileA(const char*p,unsigned acc,unsigned sh,unsigned sec,unsigned cr,unsigned at,unsigned t){
  int fl=(acc==0x80000000u)?0:1; if(cr==4)fl|=64; if(cr==2)fl|=64|512;
  int r=sys3(5,(int)p,fl,0644); return r<0?-1:r;}
int SetFilePointer(int h,int d,int hi,int m) __asm__("_SetFilePointer");
int SetFilePointer(int h,int d,int hi,int m){return sys3(19,h,d,m==2?2:0);}
int GetFileSize(int h,int hi) __asm__("_GetFileSize");
int GetFileSize(int h,int hi){int cur=sys3(19,h,0,1);int sz=sys3(19,h,0,2);sys3(19,h,cur,0);return sz;}
int WriteFile(int h,const char*b,int n,int*w,int o) __asm__("_WriteFile");
int WriteFile(int h,const char*b,int n,int*w,int o){int r=sys3(4,h,(int)b,n);*w=r;return 1;}
int ReadFile(int h,char*b,int n,int*w,int o) __asm__("_ReadFile");
int ReadFile(int h,char*b,int n,int*w,int o){int r=sys3(3,h,(int)b,n);*w=r<0?0:r;return 1;}
int CloseHandle(int h) __asm__("_CloseHandle");
int CloseHandle(int h){return sys3(6,h,0,0);}
void GetLocalTime(unsigned short*t) __asm__("_GetLocalTime");
void GetLocalTime(unsigned short*t){t[0]=2026;t[1]=11;t[2]=3;t[3]=11;t[4]=14;t[5]=5;t[6]=9;t[7]=0;}
int GetCurrentDirectoryA(int n,char*b) __asm__("_GetCurrentDirectoryA");
int GetCurrentDirectoryA(int n,char*b){const char*d="/tmp/krtest";int i=0;while(d[i]){b[i]=d[i];i++;}b[i]=0;return i;}

// ---- the assembly module ----
#define A(r,n,a) extern r n a __asm__("_" #n)
A(void,GraphReset,(int)); A(void,GraphAddEdge,(int,int,int)); A(void,SetNodePos,(int,int,int));
A(void,AddLandmark,(const char*,int)); A(void,DataInit,(void));
A(void,DijkstraInit,(int)); A(int,DijkstraStep,(void)); A(int,GetDist,(int)); A(int,GetPrev,(int));
A(int,BuildPath,(int)); A(int,GetPathLen,(void)); A(int,GetPathNode,(int)); A(void,RouteString,(char*));
A(int,NodeSX,(int)); A(int,NodeSY,(int)); A(int,HitLandmark,(int,int,int)); A(int,HitNode,(int,int));
A(void,NodeName,(int,char*)); A(int,PlaceCount,(void)); A(const char*,PlaceNameAt,(int)); A(int,PlaceNodeAt,(int));
A(int,FindPlace,(const char*));
A(int,FavSet,(int,int,int,const char*)); A(int,FavDelete,(int)); A(int,FavCount,(void)); A(int,FavNodeAt,(int));
A(int,FavTypeAt,(int)); A(const char*,FavNameAt,(int)); A(int,FavOfNodeAt,(int)); A(int,FavLoad,(void));
A(int,HistAppend,(int,int,int)); A(int,HistLoad,(void)); A(int,ClearHistory,(void)); A(int,HistCount,(void));
A(int,HistRecentN,(void)); A(const char*,HistRecentAt,(int));
A(int,AppendToFile,(const char*,const char*)); A(int,ReadWholeFile,(const char*,char*,int));
A(int,ClearFile,(const char*)); A(int,CountLines,(const char*));

static int adjm[NNODES][NNODES];
static int lmNode(const char*n){for(int k=0;k<NLM;k++)if(seq(LMS[k].name,n))return LMS[k].node;return -1;}
static int lmIdx(const char*n){for(int k=0;k<NLM;k++)if(seq(LMS[k].name,n))return k;return -1;}
static char fbuf[70000];
static int readFile(const char*p,char*b,int n){int h=sys3(5,(int)p,0,0);if(h<0){b[0]=0;return -1;}int r=sys3(3,h,(int)b,n-1);sys3(6,h,0,0);if(r<0)r=0;b[r]=0;return r;}
static void writeFile(const char*p,const char*t){int h=sys3(5,(int)p,1|64|512,0644);sys3(4,h,(int)t,slen(t));sys3(6,h,0,0);}

int main(void){
  char buf[2000]; const char* HIST="/tmp/krtest\\route_history.txt"; const char* FAV="/tmp/krtest\\favourites.txt";
  sys3(10,(int)HIST,0,0); sys3(10,(int)FAV,0,0);                    // unlink both files

  // ---- load the real Karachi map into the assembly module ----
  GraphReset(NNODES);
  for(int i=0;i<NNODES;i++)SetNodePos(i,NODE_X[i],NODE_Y[i]);
  for(int k=0;k<NLM;k++)AddLandmark(LMS[k].name,LMS[k].node);
  for(int e=0;e<NEDGES;e++)GraphAddEdge(EDGE_U[e],EDGE_V[e],EDGE_W[e]);
  DataInit();
  puts_("map loaded: ");putn(NNODES);puts_(" junctions, ");putn(NEDGES);puts_(" roads, ");putn(NLM);puts_(" areas\n");

  // ---- screen position / click handling ----
  int okpos=1; for(int i=0;i<NNODES;i++){ if(NodeSX(i)!=(int)(((long)NODE_X[i]*960+635)/1270)) okpos=0; if(NodeSY(i)!=(int)(((long)NODE_Y[i]*960+635)/1270)) okpos=0; }
  check("NodeSX/NodeSY match the scale formula",okpos);
  int hit=0; for(int k=0;k<NLM;k++){int n=LMS[k].node; if(HitNode(NodeSX(n),NodeSY(n))==n)hit++;}
  puts_("click on an area dot returns that area's junction: ");putn(hit);puts_("/");putn(NLM);puts_("\n");
  check("clicking dots mostly returns the right junction",hit>=NLM-6);
  check("click far from everything returns -1",HitNode(-500,-500)==-1);
  int sad=lmNode("Saddar"); check("HitLandmark finds Saddar within 5px",HitLandmark(NodeSX(sad)+3,NodeSY(sad)+2,225)==lmIdx("Saddar"));
  check("HitLandmark far away is -1",HitLandmark(-300,-300,144)==-1);

  // ---- places and search ----
  check("PlaceCount == NLM at start",PlaceCount()==NLM);
  check("PlaceNameAt(0)",seq(PlaceNameAt(0),LMS[0].name)); check("PlaceNodeAt(0)",PlaceNodeAt(0)==LMS[0].node);
  check("FindPlace exact lower-case",FindPlace("saddar")==lmIdx("Saddar"));
  check("FindPlace exact mixed case",FindPlace("ClIfToN")==lmIdx("Clifton"));
  check("FindPlace trims spaces",FindPlace("   clifton   ")==lmIdx("Clifton"));
  check("FindPlace prefix",FindPlace("jinnah")==lmIdx("Jinnah Airport"));
  check("FindPlace contains",FindPlace("tauheed")==lmIdx("Gulshan-e-Tauheed"));
  check("FindPlace unknown",FindPlace("zzzz")==-1);
  check("FindPlace empty",FindPlace("")==-1);
  check("FindPlace only spaces",FindPlace("    ")==-1);

  // ---- names ----
  NodeName(sad,buf); check("NodeName of area",seq(buf,"Saddar"));
  int near=-1,junc=-1; for(int i=0;i<NNODES&&(near<0||junc<0);i++){ int isl=0; for(int k=0;k<NLM;k++)if(LMS[k].node==i)isl=1; if(isl)continue; NodeName(i,buf); if(startsw(buf,"Near ")&&near<0)near=i; if(seq(buf,"Road junction")&&junc<0)junc=i; }
  check("some junctions are named 'Near <area>'",near>=0); puts_("junction without area nearby found: ");putn(junc>=0);puts_("\n");

  // ---- Dijkstra (assembly) vs an independent Dijkstra (C) ----
  for(int a=0;a<NNODES;a++)for(int b=0;b<NNODES;b++)adjm[a][b]=0;
  for(int e=0;e<NEDGES;e++){adjm[EDGE_U[e]][EDGE_V[e]]=EDGE_W[e];adjm[EDGE_V[e]][EDGE_U[e]]=EDGE_W[e];}
  int pairs[6][2]={{lmIdx("Saddar"),lmIdx("Jinnah Airport")},{lmIdx("Clifton"),lmIdx("Malir")},{lmIdx("Keamari"),lmIdx("Gulshan-e-Iqbal")},{lmIdx("Surjani Town"),lmIdx("Korangi")},{lmIdx("Landhi"),lmIdx("Orangi Town")},{lmIdx("Sea View"),lmIdx("North Karachi")}};
  int steps0=0,d0=0,s0=0,t0=0;
  for(int p=0;p<6;p++){
    int s=LMS[pairs[p][0]].node,t=LMS[pairs[p][1]].node;
    static int dd[NNODES],vis[NNODES]; for(int i=0;i<NNODES;i++){dd[i]=1<<28;vis[i]=0;} dd[s]=0;
    for(;;){int b=-1;for(int i=0;i<NNODES;i++)if(!vis[i]&&dd[i]<(1<<28)&&(b<0||dd[i]<dd[b]))b=i; if(b<0)break; vis[b]=1; for(int j=0;j<NNODES;j++)if(adjm[b][j]&&dd[b]+adjm[b][j]<dd[j])dd[j]=dd[b]+adjm[b][j];}
    DijkstraInit(s); int st=0,u; do{u=DijkstraStep();st++;}while(u!=t&&u!=-1);
    check("asm Dijkstra reaches the destination",u==t);
    check("asm distance equals independent Dijkstra",GetDist(t)==dd[t]);
    int len=BuildPath(t); check("path length > 1",len>1); check("path starts at source",GetPathNode(0)==s); check("path ends at destination",GetPathNode(len-1)==t);
    int sum=0,ok=1; for(int i=0;i+1<len;i++){int w=adjm[GetPathNode(i)][GetPathNode(i+1)]; if(!w)ok=0; sum+=w;}
    check("every path step is a real road",ok); check("path length sums to the distance",sum==GetDist(t));
    if(p==0){steps0=st;d0=GetDist(t);s0=s;t0=t;}
  }
  puts_("Saddar -> Jinnah Airport: ");putn(d0/10);puts_(".");putn(d0%10);puts_(" km, ");putn(steps0);puts_(" steps\n");
  DijkstraInit(s0); {int u; do{u=DijkstraStep();}while(u!=t0&&u!=-1);} BuildPath(t0);
  RouteString(buf); puts_("route string: ");puts_(buf);puts_("\n");
  check("route string starts with Saddar",startsw(buf,"Saddar")); check("route string ends with Jinnah Airport",has(buf,"Jinnah Airport")&&slen(buf)>14&&seq(buf+slen(buf)-14,"Jinnah Airport"));
  check("route string has arrows",has(buf," -> "));

  // ---- route history ----
  check("history empty at start",HistCount()==0&&HistRecentN()==0);
  check("HistAppend returns 1",HistAppend(s0,t0,steps0)==1);
  check("HistCount 1",HistCount()==1); check("HistRecentN 1",HistRecentN()==1);
  puts_("history line: ");puts_(HistRecentAt(0));puts_("\n");
  check("record starts '#1 Saddar -> Jinnah Airport | '",startsw(HistRecentAt(0),"#1 Saddar -> Jinnah Airport | "));
  check("record has the date",has(HistRecentAt(0),"| 11-Nov-2026 14:05:09 | "));
  check("record has km and minutes",has(HistRecentAt(0)," km | ")&&has(HistRecentAt(0)," min | "));
  check("record has steps and route",has(HistRecentAt(0)," steps | route: Saddar -> "));
  for(int i=0;i<5;i++)HistAppend(s0,t0,steps0);
  check("HistCount 6",HistCount()==6); check("HistRecentN 3",HistRecentN()==3);
  check("newest first (#6,#5,#4)",startsw(HistRecentAt(0),"#6 ")&&startsw(HistRecentAt(1),"#5 ")&&startsw(HistRecentAt(2),"#4 "));
  readFile(HIST,fbuf,sizeof(fbuf)); check("file has 6 lines with CRLF",CountLines(fbuf)==6&&has(fbuf,"\r\n#2 "));
  HistLoad(); check("HistLoad re-reads the same data",HistCount()==6&&startsw(HistRecentAt(0),"#6 "));
  ClearHistory(); check("ClearHistory empties the history",HistCount()==0&&HistRecentN()==0);
  readFile(HIST,fbuf,sizeof(fbuf)); check("history file is empty",slen(fbuf)==0);

  // ---- favourites ----
  int nA=lmNode("Saddar"),nB=lmNode("Clifton"),nC=lmNode("Korangi"),nD=lmNode("Malir");
  check("FavSet add heart",FavSet(-1,nA,'H',"  Home ")==0);
  check("FavCount 1",FavCount()==1); check("name cleaned",seq(FavNameAt(0),"Home")); check("type H",FavTypeAt(0)=='H');
  check("FavNodeAt",FavNodeAt(0)==nA); check("FavOfNodeAt",FavOfNodeAt(nA)==0&&FavOfNodeAt(nB)==-1);
  NodeName(nA,buf); check("NodeName shows the favourite first",seq(buf,"Home"));
  check("FavSet add star",FavSet(-1,nB,'S',"Hamza House")==0); check("type S",FavTypeAt(1)=='S');
  check("duplicate favourite name rejected (code 2)",FavSet(-1,nC,'S',"hamza house")==2);
  check("built-in area name rejected (code 3)",FavSet(-1,nC,'S',"saddar")==3);
  check("empty name rejected (code 1)",FavSet(-1,nC,'S',"")==1); check("spaces-only name rejected (code 1)",FavSet(-1,nC,'S',"    ")==1);
  check("favourites unchanged after rejections",FavCount()==2);
  check("pipe replaced",FavSet(-1,nC,'S',"A|B")==0&&seq(FavNameAt(2),"A B"));
  check("name cut to 40 chars",FavSet(-1,nD,'H',"0123456789012345678901234567890123456789ABCDEFGH")==0&&slen(FavNameAt(3))==40);
  check("rename + change icon",FavSet(1,nB,'H',"Cousin")==0&&seq(FavNameAt(1),"Cousin")&&FavTypeAt(1)=='H'&&FavCount()==4);
  check("renaming to its own name is allowed",FavSet(1,nB,'S',"cousin")==0&&FavTypeAt(1)=='S');
  check("place list grows with favourites",PlaceCount()==NLM+4&&seq(PlaceNameAt(NLM),"Home")&&PlaceNodeAt(NLM)==nA);
  check("FindPlace finds a favourite",FindPlace("home")==NLM&&FindPlace("cous")==NLM+1);
  check("FindPlace favourites win on prefix",FavSet(-1,lmNode("Garden"),'S',"Saddar Cafe")==0&&FindPlace("saddar c")>=NLM&&FindPlace("saddar")==lmIdx("Saddar"));
  readFile(FAV,fbuf,sizeof(fbuf)); puts_("favourites.txt:\n");puts_(fbuf);
  check("file has H and S lines",has(fbuf,"|H|Home\r\n")&&has(fbuf,"|S|cousin\r\n"));
  FavDelete(0); check("FavDelete shifts the list",FavCount()==4&&seq(FavNameAt(0),"cousin")&&FavOfNodeAt(nA)==-1&&FavOfNodeAt(nB)==0);
  check("FavDelete bad number",FavDelete(99)==1&&FavCount()==4);
  // pretend to restart the program: the favourites must come back from the file
  FavLoad(); check("FavLoad restores count",FavCount()==4);
  check("FavLoad restores names/types",seq(FavNameAt(0),"cousin")&&FavTypeAt(0)=='S'&&seq(FavNameAt(1),"A B")&&seq(FavNameAt(3),"Saddar Cafe")&&FavTypeAt(3)=='S');
  check("FavLoad restores nodes",FavNodeAt(0)==nB&&FavOfNodeAt(nB)==0);
  // old file format (no icon letter) and bad lines
  { char t[200]; int n=0;
    char x[16],y[16]; int sx=NODE_X[nA],sy=NODE_Y[nA]; int i=0; char r[16]; int j=0; unsigned v=sx; do{r[j++]='0'+v%10;v/=10;}while(v); while(j)x[i++]=r[--j]; x[i]=0;
    i=0; v=sy; do{r[j++]='0'+v%10;v/=10;}while(v); while(j)y[i++]=r[--j]; y[i]=0;
    t[0]=0; const char*parts[]={x,"|",y,"|Home\r\ngarbage line\r\n",x,"|",y,"|\r\n",x,"|",y,"|S|New Style\r\n",0};
    for(int p=0;parts[p];p++){int q=0;while(t[n]) n++; while(parts[p][q]) t[n++]=parts[p][q++]; t[n]=0;}
    writeFile(FAV,t);
    FavLoad();
    check("old format loads as heart, garbage and empty-name lines skipped",FavCount()==2&&seq(FavNameAt(0),"Home")&&FavTypeAt(0)=='H'&&seq(FavNameAt(1),"New Style")&&FavTypeAt(1)=='S'&&FavNodeAt(0)==nA);
  }
  // list full
  { int ok=1; writeFile(FAV,""); FavLoad(); for(int i=0;i<64;i++){char nm[8]="F";nm[1]='a'+(i/26);nm[2]='a'+(i%26);nm[3]=0; if(FavSet(-1,LMS[i%NLM].node,'S',nm)!=0)ok=0;} check("64 favourites can be added",ok&&FavCount()==64); check("65th favourite rejected (code 4)",FavSet(-1,nA,'S',"One too many")==4); }

  // ---- generic file helpers ----
  { const char* P="/tmp/krtest\\bigfile.txt"; sys3(10,(int)P,0,0);
    check("AppendToFile creates the file",AppendToFile(P,"0123456789")==1&&AppendToFile(P,"ABCDEFGHIJ")==1);
    char r[100]; int n=ReadWholeFile(P,r,100); check("ReadWholeFile reads everything",n==20&&seq(r,"0123456789ABCDEFGHIJ"));
    n=ReadWholeFile(P,r,8); check("ReadWholeFile with a small buffer returns the LAST bytes",n==7&&seq(r,"DEFGHIJ"));
    check("ReadWholeFile missing file returns 0",ReadWholeFile("/tmp/krtest\\nope.txt",r,100)==0&&r[0]==0);
    check("CountLines",CountLines("a\nb\r\nc\n")==3&&CountLines("")==0);
    check("ClearFile empties it",ClearFile(P)==1&&ReadWholeFile(P,r,100)==0);
    sys3(10,(int)P,0,0); }

  puts_("\n"); putn(passes);puts_(" checks passed, ");putn(fails);puts_(" failed\n");
  return fails?1:0;
}
