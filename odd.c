#include <stdio.h>
int main()
{

int VAR_0=0;
int VAR_1=0;
int VAR_2=0;
int VAR_3=0;
int VAR_4=0;
int VAR_5=0;
int VAR_6=0;
int VAR_7=0;
int VAR_8=0;
int VAR_9=0;
int* acc=&VAR_0;
LINE_0: *acc*=VAR_0;
LINE_1: acc=&VAR_1;
LINE_2: VAR_2=0;
LINE_3: printf("%d\n",VAR_3);
LINE_4: ;
LINE_5: if(VAR_4!=0) goto LINE_7;
LINE_6: *acc=VAR_5;
LINE_7: *acc-=VAR_6;
LINE_8: VAR_6--;
LINE_9: *acc=VAR_7;
LINE_10: *acc-=VAR_5;
LINE_11: *acc+=VAR_8;
LINE_12: VAR_9=0;
LINE_13: ;
LINE_14: *acc=VAR_4;
LINE_15: *acc-=VAR_4;
LINE_16: *acc-=VAR_1;
LINE_17: printf("%d\n",VAR_6);
LINE_18: *acc+=VAR_1;
LINE_19: VAR_3--;
LINE_20: *acc-=VAR_6;
LINE_21: goto LINE_1;
LINE_22: *acc=VAR_5;
LINE_23: *acc*=VAR_1;
LINE_24: *acc-=VAR_8;
}
