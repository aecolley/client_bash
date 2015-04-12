#!/bin/bash

. prometheus.bash

test_simple() {
  io::prometheus::DiscardAllMetrics
  io::prometheus::NewGauge name=start_time help='time_t when something started' || return
  io::prometheus::NewGauge name=end_time help='time_t when something ended' || return
  start_time set 1428782596 || return
  sleep 1
  end_time set 1428782597 || return
  io::prometheus::ExportToFile "/tmp/prometheus_actual_test_simple.$$" || return
  local rc=0
  diff -u - "/tmp/prometheus_actual_test_simple.$$" <<'TEST_EXPECTED_EOF' || rc=$?
# TYPE start_time gauge
# HELP start_time time_t when something started
start_time 1428782596
# TYPE end_time gauge
# HELP end_time time_t when something ended
end_time 1428782597
TEST_EXPECTED_EOF
  rm -f "/tmp/prometheus_actual_test_simple.$$"
  return ${rc}
}

# According to the client data exposition format, any leading whitespace in
# the help string will be skipped on parsing. Still, it's harmless.
test_weird_help() {
  io::prometheus::DiscardAllMetrics
  io::prometheus::NewGauge name=mojibake help=' ALL Y"OUR B\ASE
ARE BEL'\''ONG TO US' || return
  mojibake  set 23 || return
  io::prometheus::ExportToFile "/tmp/prometheus_actual_test_weird_help$$" || return
  local rc=0
  diff -u - "/tmp/prometheus_actual_test_weird_help$$" <<'TEST_EXPECTED_EOF' || rc=$?
# TYPE mojibake gauge
# HELP mojibake  ALL Y"OUR B\\ASE\nARE BEL'ONG TO US
mojibake 23
TEST_EXPECTED_EOF
  rm -f "/tmp/prometheus_actual_test_weird_help$$"
  return ${rc}
}

test_labels() {
  io::prometheus::DiscardAllMetrics
  io::prometheus::NewGauge name=falling_speed labels=faller \
    help='meters per second (terminal velocity)' || return
  falling_speed -faller=GLaDOS set 300 || return
  falling_speed -faller=Chell set 301 || return
  io::prometheus::ExportToFile "/tmp/prometheus_actual_test_labels.$$" || return
  LC_COLLATE=C sort -o "/tmp/prometheus_actual_test_labels.$$" \
    "/tmp/prometheus_actual_test_labels.$$" || return
  local rc=0
  diff -u - "/tmp/prometheus_actual_test_labels.$$" <<'TEST_EXPECTED_EOF' || rc=$?
# HELP falling_speed meters per second (terminal velocity)
# TYPE falling_speed gauge
falling_speed{faller="Chell"} 301
falling_speed{faller="GLaDOS"} 300
TEST_EXPECTED_EOF
  rm -f "/tmp/prometheus_actual_test_labels.$$"
  return ${rc}
}

test_weird_labels() {
  io::prometheus::DiscardAllMetrics
  io::prometheus::NewGauge name=alien_heart_count labels=species \
    help='vivisection results' || return
  alien_heart_count -species="'uman" set 1 || return
  alien_heart_count -species='Vl"hurg' set 7 || return
  alien_heart_count -species='Gallifreyan
' set 2 || return
  alien_heart_count -species='Cent\ari' set 2 || return
  local unicode_snowman='☃'  # U+2603
  alien_heart_count -species="${unicode_snowman}" set 0 || return
  io::prometheus::ExportToFile "/tmp/prometheus_actual_test_weird_labels.$$" || return
  LC_COLLATE=C sort -o "/tmp/prometheus_actual_test_weird_labels.$$" \
    "/tmp/prometheus_actual_test_weird_labels.$$" || return
  local rc=0
  diff -u - "/tmp/prometheus_actual_test_weird_labels.$$" <<'TEST_EXPECTED_EOF' || rc=$?
# HELP alien_heart_count vivisection results
# TYPE alien_heart_count gauge
alien_heart_count{species="'uman"} 1
alien_heart_count{species="Cent\\ari"} 2
alien_heart_count{species="Gallifreyan\n"} 2
alien_heart_count{species="Vl\"hurg"} 7
alien_heart_count{species="☃"} 0
TEST_EXPECTED_EOF
  rm -f "/tmp/prometheus_actual_test_weird_labels.$$"
  return ${rc}
}

test_setToElapsedTime() {
  io::prometheus::DiscardAllMetrics
  io::prometheus::NewGauge name=duration help='Seconds "sleep 2" took to run'
  duration setToElapsedTime sleep 2 || return
  local collection savedDuration
  collection="$(duration collect)" || return
  savedDuration="$(printf '%s\n' "${collection}" | sed -n -e 's/^duration //p')"
  case "${savedDuration}" in
  1.9*) : close enough ;;
  2)    : right on ;;
  2.0*) : close enough ;;
  *)
    printf 1>&2 'Expected "duration 2" but got:\n%s\n' "${collection}"
    return 1
  esac
  return 0
}

alltests() {
  test_simple || return
  test_weird_help || return
  test_labels || return
  test_weird_labels || return
  test_setToElapsedTime || return
}

main() {
  local rc=0
  alltests || { rc=$?; }
  if [[ ${rc} -ne 0 ]]; then
    io::prometheus::internal::DumpInternalState 1>&2
  else
    printf 'OK\n'
  fi
  return ${rc}
}

main "$@"
