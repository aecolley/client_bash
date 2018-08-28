Typical usage:

    io::prometheus::NewGauge name=start_time help='When the run began'
    start_time set "$(date +%s)"
    io::prometheus::PushAdd job=cronjob instance='' gateway=:9091

    : main cron job code goes here

    io::prometheus::NewGauge name=end_time help='When the run ended'
    end_time set "$(date +%s)"
    io::prometheus::PushAdd job=cronjob instance='' gateway=:9091

This is a library to help you push metrics from your Bash script  to a
[Prometheus pushgateway](https://github.com/prometheus/pushgateway) 
server.

It's written to use [GNU Bash](http://www.gnu.org/software/bash/)'s features,
mainly because the basic POSIX shell doesn't support the `local` keyword.

The library is still missing some essential features such as documentation
and non-gauge metrics.
