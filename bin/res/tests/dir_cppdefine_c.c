#ifndef DIR_CPPDEF_ON
#error DIR_CPPDEF_ON is not defined: the @cppdefine macros do not reach this file
#endif

/* dir_cppdefine_c.c - C source for dir_cppdefine.pcpp (see its header).
   Nothing to check here. */

int dir_cppdef_value(void)
{
  return DIR_CPPDEF_V;
}
