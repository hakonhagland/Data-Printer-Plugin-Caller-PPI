# Installation from Github

```
git clone https://github.com/hakonhagland/Data-Printer-Plugin-Caller-PPI.git
cd Data-Printer-Plugin-Caller-PPI
cpanm Dist::Zilla
dzil authordeps --missing | cpanm
dzil build
dzil test
dzil install
```
