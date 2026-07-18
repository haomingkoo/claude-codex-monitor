#!/bin/bash
set -eu

eval "$(sed -n '/^format_window_label()/,/^}/p' "$(dirname "$0")/../claude-code-monitor.2m.sh")"

[ "$(format_window_label 18000)" = "5h" ]
[ "$(format_window_label 604800)" = "7d" ]
[ "$(format_window_label 172800)" = "2d" ]
[ "$(format_window_label '')" = "limit" ]
[ "$(format_window_label unknown)" = "limit" ]

echo "Codex window label checks passed"
