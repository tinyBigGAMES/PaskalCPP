// dir_addsourcefile_cpp.C - C++ source for dir_addsourcefile.pcpp (see its
// header): C++ only (a namespace, a struct), so it builds only as C++.
// Nothing to check here.

namespace dir_asf
{
  struct Box
  {
    int v;
  };
}

extern "C" int dir_asf_twice(int a)
{
  dir_asf::Box b{a};
  return b.v * 2;
}
