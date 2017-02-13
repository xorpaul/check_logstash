![logstash](https://github.com/xorpaul/check_logstash/raw/master/logstash.png)


### Usage

```
Usage: check_logstash [options]
    -d, --debug                      print debug information, defaults to false
        --checkmk                    append HTML </br> to each line in the long output to display line breaks in the check_mk GUI, defaults to false
    -H, --host [LOGSTASHSERVER]      Your logstash hostname, MANDATORY parameter
    -p, --port [PORT]                Your logstash port, defaults to 9600
    -t, --timeout [SECONDS]          Timeout for each HTTP GET request, defaults to 5 seconds
```


### Example output

```
$ ruby check_logstash.rb -H localhost
153636 IN events 153636 OUT events 153636 filtered events 6826149 duration in ms 18% of JVM heap used (1111MB of max 5939MB) uptime: 142 hours |events_in=153636c events_out=153636c events_filtered=153636c events_dur=6826149ms heap_perc=18% heap_bytes=1111MB uptime=513181s
153636 IN events 153636 OUT events 153636 filtered events 6826149 duration in ms
18% of JVM heap used (1111MB of max 5939MB) uptime: 142 hours
```

unreachable output:

```
$ ruby check_logstash.rb -H localhost
CRITICAL: Could not connect to plain HTTP port localhost:9600 |
```
