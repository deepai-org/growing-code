#include <stdio.h>
int main()
{
int* acc;
int VAR_0;
int VAR_1;
int VAR_2;
LINE_0: VAR_0=0;
LINE_1: acc=&VAR_1;
LINE_2: *acc=10;
LINE_3: acc=&VAR_2;
LINE_4: *acc=VAR_0;
LINE_5: *acc-=VAR_1;
LINE_6: if(VAR_2!=0) goto LINE_8;
LINE_7: return 0;
LINE_8: VAR_0++;
LINE_9: printf("%d\n",VAR_0);
LINE_10: goto LINE_3;
}
