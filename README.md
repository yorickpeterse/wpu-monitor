# Itho WPU Monitor

A simple [Fish](https://fishshell.com/) for monitoring the status of an Itho
Daalderop heatpump using the [Itho WiFi
module](https://github.com/arjenhiemstra/ithowifi), and sending it to an
InfluxDB/VictoriaMetrics database.

The script also supports controlling the outside temperature of the WPU, using
[Buienradar](https://www.buienradar.nl/) as the temperature source. For this to
work, you need to set `WEATHER_STATION_ID` to a Buienradar `stationid` value as
found in [this JSON response](https://data.buienradar.nl/2.0/feed/json).

# License

All source code in this repository is licensed under the Mozilla Public License
version 2.0, unless stated otherwise. A copy of this license can be found in the
file "LICENSE".
