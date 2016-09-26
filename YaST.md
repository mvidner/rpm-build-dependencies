# Reducing Rebuild Time by 30%

How we reduced the critical path of the rebuild time of YaST RPM packages
from 42min 2s to 29min 40s.

## Where to Optimize

1. know the dependencies
2. know the individual build times

1

(it is tempting to figure out the dependencies by yourself, by parsing the spec
files.)

use `osc dependson`

2

`osc getbinaries` produces the RPMs, and _statistics (also _buildenv and
rpmlint.log)

example: (make it an endnote)

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

## How to Optimize

## Results

The build dependency graph before our fixes:

![build dependency graph before][before]

The build dependency graph after our fixes:

![build dependency graph after][after]

[before]: yast_deps_before.png
[after]:  yast_deps_after.png
