# Copyright 2015 Adrian Colley <aecolley@gmail.com>
# Copying, adaptation and redistribution are permitted subject
# to the terms in the accompanying LICENSE file (Apache 2.0).
#
# This is an attempt at a Prometheus Bash client library.
# This is broadly based on the Go client library, but simplified.
# All metrics are automatically registered at creation time.
# Metric options don't have Namespace or Subsystem because shell scripts
# can do the concatenation more clearly themselves. They don't have
# ConstLabels because those are hard to construct while quoting everything
# safely. Because all the metrics must have a distinct (fully-qualified) name,
# their structures are all named after that name.

# Notably missing from this script:
# + User documentation
# + Labels
# + Counter metrics
# + Summary metrics
# + Proper escaping of help strings and label values
# + Unit tests
# + A fallback if no "curl" is available (maybe "wget")

# A design note: to keep the namespace from being polluted, this file defines
# exactly one parameter and exactly one function, both called "prometheus".
# The parameter is an associative array, so its keys are used like normal
# variable names. The function's first argument is used to select the actual
# procedure to run. This is either highly efficient or plain crazy.

# Example use:
# prometheus NewGauge name=start_time help='time_t when cron job last started'
# start_time set $(date +'%s.%N')
# prometheus PushAdd cronjob $HOSTNAME pushgateway0:9091

# An example with labels (which doesn't work yet):
# prometheus NewGauge name=start_time help='time_t when cron job last started' \
#   labels=host,runmode
# start_time -host=spof0 -runmode=PRODUCTION set $(date +'%s.%N')
# prometheus PushAdd cronjob $HOSTNAME pushgateway0:9091

# Prometheus client_bash data are all stored in one associative array.
declare -A prometheus=()

# The keys in $prometheus are (with example values from the second example above):
# "METRIC:start_time{host="spof0",runmode="PRODUCTION"}"
#   This is a value of a metric, in the client data exposition format
#   (i.e. \n, \", and \\ are escape sequences).
#
# "HELP:start_time"
#   This is the help string for a metric, in the client data exposition format
#   (i.e. \n and \\ are escape sequences).
#
# "TYPE:start_time"
#   This is the type ("gauge", "counter", "summary", or "untyped") of the metric.

prometheus() {
  local backslash=\\
  local linefeed='
'
  [[ $# -ge 1 ]] || {
    printf 1>&2 'FATAL: prometheus called without arguments.\n'
    exit 2
  }
  case "$1" in
  NewGauge)
    local arg help='' name=''
    shift
    # Parse the options on the NewGauge command line.
    for arg; do
      case "${arg}" in
      help=*) help="${arg#*=}";;
      name=*) name="${arg#*=}";;
      *)
        printf 1>&2 'FATAL: %s: bad arg "%s"\n' "prometheus NewGauge" "${arg}"
        exit 2
      esac
    done
    if [[ -z "${help}" || -z "${name}" ]]; then
      printf 1>&2 'ERROR: %s: missing required option (help or name)\n' \
        "prometheus NewGauge"
      return 1
    fi
    # Validate the options.
    if [[ "${name}" =~ ^[a-zA-Z_:][a-zA-Z0-9_:]*$ ]]; then
      if [[ -n "${prometheus["TYPE:${name}"]}" ]]; then
        printf 1>&2 'WARNING: %s: "%s" already a registered %s metric.\n' \
          "prometheus NewGauge" "${name}" "${prometheus["TYPE:${name}"]}"
      fi
    else
      printf 1>&2 'FATAL: %s: Invalid metric name "%s"\n' \
        "prometheus NewGauge" "${name}"
      exit 2
    fi
    prometheus["TYPE:${name}"]="gauge"
    prometheus["HELP:${name}"]="$(prometheus internal-escape-help "${help}")"
    eval "${name}"'() { prometheus internal-Gauge '"${name}"' "$@"; }'
    ;;

  PushAdd)
    shift
    [[ $# -eq 3 ]] || {
      printf 1>&2 'FATAL: %s called with %s arguments (expected %s)\n' \
        'prometheus PushAdd' $# 3
      exit 2
    }
    local job="$1"
    local instance="$2"
    local target="$3"
    # Collect the names of all the exportable metrics.
    local -a metricnames=()
    local key
    for key in "${!prometheus[@]}"; do
      if [[ "${key}" =~ ^TYPE: ]]; then
        metricnames+=("${key#TYPE:}")
      fi
    done
    # Construct the payload to push.
    local payload=''
    local name
    for name in "${metricnames[@]}"; do
      payload="${payload}# TYPE ${name} ${prometheus["TYPE:${name}"]}${linefeed}"
      payload="${payload}# HELP ${name} ${prometheus["HELP:${name}"]}${linefeed}"
      for key in "${!prometheus[@]}"; do
        if [[ "${key}" =~ ^METRIC:"${name}"([{].*)?$ ]]; then
          payload="${payload}${key#METRIC:} ${prometheus["${key}"]}${linefeed}"
        fi
      done
    done
    # Construct the URL to push to.
    local url
    case "${target}" in
    :*)  url="http://localhost${target}/metrics/jobs/${job}";;
    *:*) url="http://${target}/metrics/jobs/${job}";;
    *)   url="http://${target}:9091/metrics/jobs/${job}"
    esac
    if [[ -n "${instance}" ]]; then
      url="${url}/instances/${instance}"
    fi
    # POST the payload to the URL.
    #echo -En "${payload}" | sed 's/^/payload>/' 1>&2
    curl -q \
      --data-binary '@-' <<<"${payload}" \
      --user-agent 'Prometheus-client_bash/prerelease' \
      --fail \
      --silent \
      --connect-timeout 5 \
      --max-time 10 \
      "${url}" > /dev/null
    ;;

  internal-escape-help)
    # Escape a help-string as required by the client data exposition format.
    # Backslash and linefeed are escaped.
    case "$2" in
    *"${backslash}"*|*"${linefeed}"*)
      printf 1>&2 'FATAL: prometheus internal-escape-help unimplemented.\n'
      exit 2
      ;;
    *)
      printf '%s\n' "$2"
    esac
    ;;

  internal-Gauge)
    # This handles all calls to Gauges (each Gauge is a shell function).
    local name="$2"
    shift 2
    local subcmd=''
    local -A label=()
    while [[ $# -ge 1 ]]; do
      local arg="$1"
      shift
      case "$arg" in
      -*=*)
        label["${arg%%'='*}"]="${arg#*=}"
        # Note: the label keys still begin with '-'.
        ;;
      *)
        subcmd="$arg"
        break
      esac
    done
    # We'll need the key and value of this gauge
    local key value
    key="METRIC:${name}"
    # TODO(aecolley): Add the labels to the key.
    value="${prometheus["${key}"]:-0}"
    # Dispatch the subcommand for this Gauge function.
    case "${subcmd}" in
    'set')
      # TODO(aecolley): check that $1 is a number
      prometheus["${key}"]="$1";;
    'inc')
      prometheus["${key}"]="$(prometheus internal-add "${value}" 1)";;
    'dec')
      prometheus["${key}"]="$(prometheus internal-add "${value}" -1)";;
    'add')
      prometheus["${key}"]="$(prometheus internal-add "${value}" "$1")";;
    'sub')
      prometheus["${key}"]="$(prometheus internal-sub "${value}" "$1")";;
    '')
      printf 1>&2 'FATAL: %s function called without a subcommand.\n' "${name}"
      exit 2
      ;;
    *)
      printf 1>&2 'FATAL: %s function called with unknown subcommand "%s".\n' \
        "${name}" "${subcmd}"
      exit 2
    esac
    ;;

  internal-add)
    local a="$2"
    local b="$3"
    # TODO(aecolley): Add an awkless path for adding int32s.
    # We insert a '+' before nonnegative numbers, because GNU awk recognises
    # "+nan" as numeric, but not "nan".
    [[ "$a" =~ ^[^-] ]] && a="+${a}"
    [[ "$b" =~ ^[^-] ]] && b="+${b}"
    awk -v "a=${a}" -v "b=${b}" 'BEGIN { printf "%.16g\n", a + b; exit 0 }'
    ;;

  internal-sub)
    if [[ "$2" =~ ^- ]]; then
      prometheus internal-add "$1" "${2#'-'}"
    else
      prometheus internal-add "$1" "-$2"
    fi
    ;;

  *)
    printf 1>&2 'FATAL: prometheus called with unknown subcommand "%s".\n' "$1"
    exit 2
  esac
}
