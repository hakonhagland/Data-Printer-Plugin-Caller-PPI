# Installation from Github

```
git clone https://github.com/hakonhagland/Data-Printer-Plugin-Caller-PPI.git
cd Data-Printer-Plugin-Caller-PPI
cpanm --quiet --notest Dist::Zilla
dzil authordeps --missing | cpanm --quiet --notest
dzil listdeps | cpanm --quiet --notest
dzil test
dzil install
```
