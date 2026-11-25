#!/bin/bash
# ------------------------------------------------------------------------------
# Recreate the report figure with the inner loop of Potential(), scalar vs SVE.
#
# For each binary: disassemble Potential(), take the innermost loop (from the
# target of the first backward b.ne down to that branch), drop the addresses,
# and print it inside the LaTeX figure* used in the report (label fig:asm).
# In the SVE build, the faddv right after the loop (sum of the 8 lanes) is kept.
#
# Usage, from wa1_jj/ (binaries come from scripts/run_a_serial.sh):
#   ./scripts/visualizations/asm_figure.sh \
#       results/deucalion/md_a_serial_novec/md_profiling \
#       results/deucalion/md_a_serial_vec/md_profiling > figure_asm.tex
# Works on the laptop (aarch64-linux-gnu-objdump) and on Deucalion (objdump).
# ------------------------------------------------------------------------------
set -euo pipefail

[ $# -eq 2 ] || { echo "Usage: $0 <novec binary> <vec binary>" >&2; exit 1; }
NOVEC=$1
VEC=$2
FUNCTION="Potential()"

OBJDUMP=objdump
command -v aarch64-linux-gnu-objdump > /dev/null && OBJDUMP=aarch64-linux-gnu-objdump

# Assembly of one function: from "<name>:" to the next blank line.
show_function() {
    $OBJDUMP --disassemble --demangle --no-show-raw-insn "$1" |
        awk -v start="<$FUNCTION>:" '
            index($0, start) { inside = 1; next }
            inside && /^$/   { exit }
            inside           { print }'
}

# Innermost loop, one instruction per line, without addresses.
# objdump line:   "  401640:\tldp\td30, d29, [x0]"   (fields split by tabs)
inner_loop() {
    show_function "$1" | awk -F'\t' '
        { addr[NR] = $1; op[NR] = $2; args[NR] = $3; sub(/ *\/\/.*/, "", args[NR]) }
        END {
            for (b = 1; b <= NR; b++) {
                if (op[b] != "b.ne") continue
                split(args[b], t, " ")                  # t[1] = branch target address
                for (s = 1; s < b; s++)
                    if (addr[s] ~ "^ *" t[1] ":$") break
                if (s == b) continue                    # forward branch: not a loop
                args[b] = "<loop>"
                last = b
                if (op[b + 1] == "faddv") { last = b + 1; args[last] = args[last] "    // after loop" }
                width = 7                               # align operands in one column
                for (i = s; i <= last; i++) if (length(op[i]) + 1 > width) width = length(op[i]) + 1
                format = "%-" width "s%s\n"
                for (i = s; i <= last; i++) printf format, op[i], args[i]
                exit
            }
            print "No backward b.ne found: no loop to extract" > "/dev/stderr"
            exit 1
        }'
}

SCALAR_LOOP=$(inner_loop "$NOVEC")
SVE_LOOP=$(inner_loop "$VEC")

cat <<EOF
\begin{figure*}[!t]
\centering
\begin{minipage}[t]{0.42\textwidth}
\footnotesize
\textbf{novec} (scalar)
\begin{verbatim}
$SCALAR_LOOP
\end{verbatim}
\end{minipage}
\hfill
\begin{minipage}[t]{0.52\textwidth}
\footnotesize
\textbf{vec} (SVE, up to 8 pairs per iteration)
\begin{verbatim}
$SVE_LOOP
\end{verbatim}
\end{minipage}
\caption{Inner loop over \$j\$ of \texttt{Potential()} (Alternative A),
non-vectorized (left) and vectorized with SVE (right).}
\label{fig:asm}
\end{figure*}
EOF
