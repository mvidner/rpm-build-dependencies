# RPM Build Dependencies

The [Open Build Service][obs] builds lots of Linux packages. You may have a
project of dozens of such packages, which all depend on one another. You want
to reduce the build time dependencies to make it easier to do a full rebuild.

This repo helps with that.

So far we have concentrated on solving the [problem][dabug] for
one particular case, the [YaST project][yast]:

```console
$ ruby print_deps.rb YaST:Head openSUSE_Factory x86_64 yast_deps.yaml
```

[obs]: http://openbuildservice.org/
[dabug]: https://bugzilla.suse.com/show_bug.cgi?id=999203
[yast]: https://build.opensuse.org/project/show?project=YaST%3AHead
