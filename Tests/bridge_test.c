#include "E4Emulator.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv){
  E4Emulator* e=e4_create(argv[1],"/tmp/t.sav");
  if(!e){printf("load failed\n");return 1;}
  unsigned w,h; e4_video_size(e,&w,&h);
  char t[32]; e4_title(e,t,32);
  printf("sys=%d %ux%u fps=%.2f rate=%u title=%s\n",e4_system(e),w,h,e4_fps(e),e4_sample_rate(e),t);
  int16_t buf[8192]; size_t total=0;
  for(int i=0;i<120;i++){ e4_set_buttons(e,i%2?E4ButtonStart:0); e4_run_frame(e); total+=e4_read_audio(e,buf,4096);}
  printf("audio frames=%zu\n",total);
  size_t sz=e4_state_size(e); void*s=malloc(sz); size_t wr=0;
  printf("state size=%zu save=%d ",sz,e4_save_state(e,s,sz,&wr,false));
  printf("written=%zu load=%d\n",wr,e4_load_state(e,s,wr));
  printf("file save=%d load=%d\n",e4_save_state_file(e,"/tmp/t.ss"),e4_load_state_file(e,"/tmp/t.ss"));
  printf("cheat ok=%d bad=%d\n",e4_add_cheat(e,"x","3E000000 00000000"),e4_add_cheat(e,"y","zzz"));
  e4_destroy(e); printf("done\n"); return 0;}
