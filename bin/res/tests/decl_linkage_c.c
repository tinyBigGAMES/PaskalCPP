/* decl_linkage_c.c - C source for decl_linkage.pcpp (see its header): it
   calls the clink routine decl_linkage_triple by its plain C name, which
   links only because clink gives the routine C linkage.
   Nothing to check here. */

int decl_linkage_triple(int AN);

int decl_linkage_from_c(int AN)
{
  return decl_linkage_triple(AN) + 1;
}
