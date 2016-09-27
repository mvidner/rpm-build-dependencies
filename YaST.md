# Reducing Rebuild Time by 30%

How we reduced the critical path of the rebuild time of YaST RPM packages
from 42min 2s to 29min 40s.

## Where to Optimize

This breaks down into

1. knowing the dependencies, and
2. knowing the individual build times.

### Dependencies

It is tempting to figure out the dependencies by yourself, by parsing the spec
files. But it is hard to do right, and, more importantly, a reinvention of the
wheel. The Build Service must know all this to be able to schedule the builds,
and provides a convenient way to access it, with `osc dependson`:

```console
$ osc dependson YaST:Head openSUSE_Factory x86_64
[...]
yast2-x11 :
   yast2-devtools
yast2-xml :
   yast2-core
   yast2-devtools
yast2-ycp-ui-bindings :
   libyui
   yast2-core
   yast2-devtools
```

### Individual Build Times

For each source package, the Build Service produces not only binary RPMs but
also a `_statistics` file, available in the [web UI][webstats] or via
`osc getbinaries`. We are interested in the total build time. (The data is of
limited usability though, because packages can be built on machines with
vastly different power and this information is not included.)

For an example, see the [Build Statistics](#build-statistics) section
at the end.

[webstats]: https://build.opensuse.org/package/statistics/YaST:Head/yast2-core?arch=x86_64&repository=openSUSE_Factory

## How to Optimize

### Stop Using Autotools

Automake, autoconf, and configure, take up a majority of the time needed for
building pure Ruby packages. They check for portablility problems that we
don't have. They are a leftover from the times 15 years back
when they were the only sensible option. Now we do not really
need them and have been using https://github.com/openSUSE/packaging_rake_tasks

### Stub the APIs Used in Tests

Ruby is a dynamic language and makes it easy to replace interfaces by stubs.

Well, we also have some Perl code (notably yast2-users), and the stubbing
techniques across languages are messier but still effective.

### Do not Build Specialized Documentation

If the docs is only useful to people that will check out the git repo anyway
then leave it out from the RPM.

## The Details

### Dependency Graphs

In the graphs below, a node is a source package in the build service, and an
arrow means "needs for its build". Redundant arrows are omitted (that is, we've
erased an A→C if both A→B and B→C existed).

We can see that the most prominent feature is that there is a large number of
packages that depend on yast2, a collection of basic libraries.

But on top of that, in the original graph there are 6 more layers, and the
graph is not very dense there. After our fixes, there are only 4 layers that
are more dense.

(TODO: the "layer" concept only works if the packages take roughly the same
time to build; it would not be helpful if there were huge variations. We
should show a histogram of build times.)

The build dependency graph before our fixes:

![build dependency graph before][before]

The build dependency graph after our fixes:

![build dependency graph after][after]

[before]: yast_deps_before.png
[after]:  yast_deps_after.png

### Build Statistics

```xml
<buildstatistics>
  <disk>
    <usage>
      <size unit="M">1118</size>
      <io_requests>15578</io_requests>
      <io_sectors>2156642</io_sectors>
    </usage>
  </disk>
  <memory>
    <usage>      <size unit="M">580</size> </usage>
  </memory>
  <times>
    <total>      <time unit="s">756</time> </total>         <!-- THIS -->
    <preinstall> <time unit="s">8</time>   </preinstall>
    <install>    <time unit="s">72</time>  </install>
    <main>       <time unit="s">555</time> </main>
    <download>   <time unit="s">4</time>   </download>
  </times>
  <download>
    <size unit="k">33564</size>
    <binaries>53</binaries>
    <cachehits>24</cachehits>
    <preinstallimage>preinstallimage.preinstallimage.tar.gz</preinstallimage>
  </download>
</buildstatistics>
```
