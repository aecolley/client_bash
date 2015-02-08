Typical usage:

    prometheus NewGauge name=start_time help='When the run began'
    start_time set "$(date +%s)"
    prometheus PushAdd cronjob '' :9091

    : main cron job code goes here

    prometheus NewGauge name=end_time help='When the run ended'
    end_time set "$(date +%s)"
    prometheus PushAdd cronjob '' :9091

This is a library to help you push metrics from your Bash script  to a
[Prometheus pushgateway](https://github.com/prometheus/pushgateway) 
server.

It's written to use [GNU Bash](http://www.gnu.org/software/bash/)'s features,
mainly because the basic POSIX shell doesn't support the `local` keyword.

This is a very early form of the library, and it is missing many essential
features such as labels and documentation.
