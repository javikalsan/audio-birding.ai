# xeno canto downloader script

## Description

A simple bash script to download [xeno canto](https://www.xeno-canto.org/) audio files in parallel

## Examples

* Download all query results of Dendrocopos leucotos

```
./xeno-canto-search-downloader.sh -q "Dendrocopos leucotos" -d
```

* Download all query results of Dendrocopos leucotos with size file below 10000 bytes

```
./xeno-canto-search-downloader.sh -q "Dendrocopos leucotos" -d -s 10000
```

## Todo

* Limit number of downloads
* Save audios to custom path
* Filter by country, region
