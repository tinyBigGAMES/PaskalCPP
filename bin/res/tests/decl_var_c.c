/* decl_var_c.c - C source for decl_var.pcpp (see its header): the C symbol
   its external variable binds, and a reader that sees what PaskalCPP wrote.
   Nothing to check here. */

int decl_var_counter = 41;

int decl_var_read(void)
{
  return decl_var_counter;
}
