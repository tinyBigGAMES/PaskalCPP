/* lib_plain_host.c - the C consumer of lib_plain, built by another toolchain
   (see lib_plain.pcpp's header). Nothing to check here. */

#include <stdio.h>

int lib_plain_add(int a, int b);

int main(void)
{
  printf("from C: lib_plain_add(2, 3) = %d\n", lib_plain_add(2, 3));
  return 0;
}
