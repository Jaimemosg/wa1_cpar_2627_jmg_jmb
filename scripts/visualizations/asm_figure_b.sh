#!/bin/bash
# ------------------------------------------------------------------------------
# Recreate the report figures with the inner loops of Potential() and
# computeAccelerations() in src/md_b, scalar (novec) vs vectorized (vec).
#
# For each function and binary: disassemble the function (falling back to its
# OpenMP outlined clone "[clone ._omp_fn.0]" when compiled with -fopenmp),
# extract the innermost pairwise interaction loop (first backward b.ne / jne
# loop containing a floating-point division, which skips the zero-init loop in
# computeAccelerations()), drop the addresses, and emit LaTeX figure* blocks.
# In an SVE build, a trailing faddv right after the loop is kept.
#
# Usage, from the project root (binaries come from scripts/run_serial.sh md_b):
#   ./scripts/visualizations/asm_figure_b.sh \
#       results/deucalion/md_b_serial_novec/md_profiling \
#       results/deucalion/md_b_serial_vec/md_profiling > figure_asm_b.tex
#
# Single-binary mode (inspect one binary, e.g. an OpenMP or local build):
#   ./scripts/visualizations/asm_figure_b.sh src/md_b/md_profiling > figure_asm_b.tex
#
# Works on a laptop (aarch64-linux-gnu-objdump for ARM64, objdump for x86-64)
# and on Deucalion (objdump).
# ------------------------------------------------------------------------------
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <novec binary> <vec binary>" >&2
    echo "   or: $0 <single binary>" >&2
    exit 1
fi

FUNCTIONS=("Potential()" "computeAccelerations()")

# Choose the right objdump for a binary's architecture.
pick_objdump() {
    local binary=$1
    if [ ! -f "$binary" ]; then
        echo "Error: binary '$binary' not found." >&2
        exit 1
    fi
    if command -v file > /dev/null && file -b "$binary" | grep -qi "aarch64"; then
        if command -v aarch64-linux-gnu-objdump > /dev/null; then
            echo aarch64-linux-gnu-objdump
            return
        fi
        if ! objdump --info 2>/dev/null | grep -qi "aarch64"; then
            echo "Error: '$binary' is ARM aarch64, but no aarch64 objdump is installed." >&2
            echo "Install binutils-aarch64-linux-gnu or run this script on Deucalion." >&2
            exit 1
        fi
    fi
    echo objdump
}

# Disassembly of one symbol: from "<symbol>:" to the next blank line.
# Avoid exiting awk early so objdump never receives SIGPIPE under pipefail.
show_symbol() {
    local objdump_bin=$1 binary=$2 symbol=$3
    "$objdump_bin" --disassemble --demangle --no-show-raw-insn "$binary" |
        awk -v start="<$symbol>:" '
            !done && index($0, start) { inside = 1; next }
            inside && /^$/            { inside = 0; done = 1; next }
            inside                    { print }'
}

# Extract the innermost pairwise loop (backward b.ne / jne containing an FP div),
# preferring the shortest vectorized loop (SVE z*.d or x86 packed SIMD) so that
# scalar helper/diagonal loops (e.g. addDiagonalTile in md_c) are skipped when
# an SVE-vectorized loop exists. Formatted as one instruction per line without addresses.
extract_pairwise_loop() {
    awk '
        /^[[:space:]]*[0-9a-f]+:/ {
            n++
            line = $0
            sub(/^[[:space:]]+/, "", line)
            colon = index(line, ":")
            addr[n] = substr(line, 1, colon - 1)
            rest = substr(line, colon + 1)
            sub(/^[[:space:]]+/, "", rest)
            sub(/[[:space:]]*\/\/.*$/, "", rest)         # ARM64 objdump comments
            sub(/[[:space:]]+#[[:space:]].*$/, "", rest) # x86-64 objdump comments
            if (match(rest, /[[:space:]]+/)) {
                op[n]   = substr(rest, 1, RSTART - 1)
                args[n] = substr(rest, RSTART + RLENGTH)
            } else {
                op[n]   = rest
                args[n] = ""
            }
        }
        END {
            best_s = 0; best_b = 0; best_vec = -1; best_len = 1000000
            for (b = 1; b <= n; b++) {
                if (op[b] != "b.ne" && op[b] != "jne") continue
                split(args[b], t, /[[:space:]]+/)       # t[1] = branch target address
                for (s = 1; s < b; s++)
                    if (addr[s] == t[1]) break
                if (s == b) continue                    # forward branch: not a loop

                # Require a floating-point division inside the loop to skip helper loops
                # such as the acceleration zero-initialization in computeAccelerations().
                has_fdiv = 0
                is_vec = 0
                for (i = s; i <= b; i++) {
                    if (op[i] ~ /^(fdiv|fdivr|v?div[sp]d)$/) has_fdiv = 1
                    if (args[i] ~ /(^|[^[:alnum:]_])z[0-9]+\.d([^[:alnum:]_]|$)/ ||
                        op[i] ~ /^v?(add|sub|mul|div|fmadd[0-9]*)pd$/) is_vec = 1
                }
                if (!has_fdiv) continue

                len = b - s + 1
                if (is_vec > best_vec || (is_vec == best_vec && len < best_len)) {
                    best_s = s; best_b = b; best_vec = is_vec; best_len = len
                }
            }
            if (best_s == 0) exit 1

            args[best_b] = "<loop>"
            last = best_b
            if (op[best_b + 1] == "faddv") {
                last = best_b + 1
                args[last] = args[last] "    // after loop"
            }
            width = 7                                   # align operands in one column
            for (i = best_s; i <= last; i++)
                if (length(op[i]) + 1 > width) width = length(op[i]) + 1
            format = "%-" width "s%s\n"
            for (i = best_s; i <= last; i++) printf format, op[i], args[i]
            exit 0
        }'
}

# Find the inner loop in <func> or, for OpenMP builds, <func [clone ._omp_fn.0]>.
inner_loop() {
    local objdump_bin=$1 binary=$2 func=$3 loop
    if loop=$(show_symbol "$objdump_bin" "$binary" "$func" | extract_pairwise_loop); then
        printf '%s\n' "$loop"
        return 0
    fi
    if loop=$(show_symbol "$objdump_bin" "$binary" "$func [clone ._omp_fn.0]" | extract_pairwise_loop); then
        printf '%s\n' "$loop"
        return 0
    fi
    echo "Error: no pairwise inner loop found for '$func' in '$binary'" >&2
    exit 1
}

# Describe whether an extracted loop uses vector instructions (SVE or x86 SIMD).
loop_kind() {
    local loop=$1
    if printf '%s\n' "$loop" | grep -Eq '\bz[0-9]+\.d\b'; then
        echo "sve"
    elif printf '%s\n' "$loop" | grep -Eq '\b(v?addpd|v?subpd|v?mulpd|v?divpd|v?fmadd[0-9]*pd)\b'; then
        echo "simd"
    else
        echo "scalar"
    fi
}

label_suffix() {
    case "$1" in
        "Potential()")            echo "potential" ;;
        "computeAccelerations()") echo "accel" ;;
        *)                        echo "$1" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' ;;
    esac
}

emit_comparison_figure() {
    local func=$1 scalar_loop=$2 vec_loop=$3
    local kind vec_heading vec_caption suffix
    kind=$(loop_kind "$vec_loop")
    suffix=$(label_suffix "$func")

    case "$kind" in
        sve)
            vec_heading="\\textbf{vec} (SVE, up to 8 pairs per iteration)"
            vec_caption="vectorized with SVE (right)"
            ;;
        simd)
            vec_heading="\\textbf{vec} (SIMD vectorized)"
            vec_caption="vectorized with SIMD (right)"
            ;;
        *)
            vec_heading="\\textbf{vec} (scalar, not vectorized)"
            vec_caption="compiled with vectorization enabled, remaining scalar (right)"
            ;;
    esac

    cat <<EOF
\begin{figure*}[!t]
\centering
\begin{minipage}[t]{0.42\textwidth}
\footnotesize
\textbf{novec} (scalar)
\begin{verbatim}
$scalar_loop
\end{verbatim}
\end{minipage}
\hfill
\begin{minipage}[t]{0.52\textwidth}
\footnotesize
$vec_heading
\begin{verbatim}
$vec_loop
\end{verbatim}
\end{minipage}
\caption{Inner loop over \$j\$ of \texttt{$func} (Alternative B),
non-vectorized (left) and $vec_caption.}
\label{fig:asm-b-$suffix}
\end{figure*}
EOF
}

if [ $# -eq 2 ]; then
    NOVEC=$1
    VEC=$2
    OBJDUMP_NOVEC=$(pick_objdump "$NOVEC")
    OBJDUMP_VEC=$(pick_objdump "$VEC")
    first=1
    for func in "${FUNCTIONS[@]}"; do
        SCALAR_LOOP=$(inner_loop "$OBJDUMP_NOVEC" "$NOVEC" "$func")
        VEC_LOOP=$(inner_loop "$OBJDUMP_VEC" "$VEC" "$func")
        [ "$first" -eq 0 ] && echo
        emit_comparison_figure "$func" "$SCALAR_LOOP" "$VEC_LOOP"
        first=0
    done
else
    BIN=$1
    OBJDUMP_BIN=$(pick_objdump "$BIN")
    POT_LOOP=$(inner_loop "$OBJDUMP_BIN" "$BIN" "Potential()")
    ACC_LOOP=$(inner_loop "$OBJDUMP_BIN" "$BIN" "computeAccelerations()")
    kind_label() {
        case "$1" in
            sve)  echo "SVE, 512-bit vectors" ;;
            simd) echo "SIMD vectorized" ;;
            *)    echo "scalar" ;;
        esac
    }
    POT_LABEL=$(kind_label "$(loop_kind "$POT_LOOP")")
    ACC_LABEL=$(kind_label "$(loop_kind "$ACC_LOOP")")
    cat <<EOF
\begin{figure*}[!t]
\centering
\begin{minipage}[t]{0.46\textwidth}
\footnotesize
\textbf{Potential()} ($POT_LABEL)
\begin{verbatim}
$POT_LOOP
\end{verbatim}
\end{minipage}
\hfill
\begin{minipage}[t]{0.48\textwidth}
\footnotesize
\textbf{computeAccelerations()} ($ACC_LABEL)
\begin{verbatim}
$ACC_LOOP
\end{verbatim}
\end{minipage}
\caption{Vectorized inner loops of \texttt{Potential()} (left) and
\texttt{computeAccelerations()} (right) (\emph{vec} build).}
\label{fig:asm-c}
\end{figure*}
EOF
fi
