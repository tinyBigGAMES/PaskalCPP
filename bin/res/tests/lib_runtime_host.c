/* lib_runtime_host.c - the C consumer of lib_runtime, built by another
   toolchain (see lib_runtime.pcpp's header). Nothing to check here. */

#include <stdio.h>

int lib_rt_div(int a, int b);

int main(void)
{
  printf("from C: lib_rt_div(7, 2) = %d\n", lib_rt_div(7, 2));
  return 0;
}
