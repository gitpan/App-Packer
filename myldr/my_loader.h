#ifndef __MY_LOADER_H
#define __MY_LOADER_H

int my_loader_init();
int my_loader_init_perl();
void my_loader_cleanup_perl();
void my_loader_cleanup();
/* returns a code reference */
SV* my_loader_get_inc_hook();
/* returns the name of the main script */
const char* my_loader_get_script_name();

#endif /* __MY_LOADER_H */
