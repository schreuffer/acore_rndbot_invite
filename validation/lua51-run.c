#include <stdio.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
int main(int argc, char **argv) {
 lua_State *L=luaL_newstate(); luaL_openlibs(L);
 int parse=argc>1 && strcmp(argv[1],"-p")==0;
 for(int i=parse?2:1;i<argc;i++) {
  if(luaL_loadfile(L,argv[i]) || (!parse && lua_pcall(L,0,LUA_MULTRET,0))) {
   fprintf(stderr,"%s\n",lua_tostring(L,-1));lua_close(L);return 1;
  }
  lua_settop(L,0);
 }
 lua_close(L);return 0;
}
