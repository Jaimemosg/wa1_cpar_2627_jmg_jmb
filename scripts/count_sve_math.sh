#!/bin/bash
# ------------------------------------------------------------------------------
# Is a function vectorized with SVE?
#
# Counts the math instructions (add, sub, mul, div, fused multiply-add, sqrt)
# that work on SVE vector registers z0..z31 holding doubles (".d").
#   count > 0  -> the function's calculations are vectorized
#   count = 0  -> the calculations are scalar
#
# Run on a Deucalion ARM node, from wa1_jj/:
#   ./scripts/count_sve_math.sh results/md_a_serial_vec/md_profiling results/md_a_serial_novec/md_profiling
# ------------------------------------------------------------------------------

FUNCTIONS=("Potential()" "computeAccelerations()")

SVE_REGISTER='z[0-9]+\.d'                                       # e.g. z31.d
MATH_INSTRUCTIONS='fadd|fsub|fmul|fdiv|fdivr|fmla|fmls|fmad|fmsb|fsqrt'

# Print the assembly of a single function (from "<name>:" to the next blank line).
show_function() {
    local binary=$1 function_name=$2
    objdump --disassemble --demangle "$binary" |
        awk -v start="<$function_name>:" '
            index($0, start) { inside = 1; next }   # function begins
            inside && /^$/   { exit }               # blank line: function ends
            inside           { print }'
}

for binary in "$@"; do
    echo "$binary"
    for function_name in "${FUNCTIONS[@]}"; do
        count=$(show_function "$binary" "$function_name" |
                grep -E "\b$SVE_REGISTER\b" |               # keep lines using SVE registers
                grep -cE "\s($MATH_INSTRUCTIONS)\s")        # count the math ones
        echo "  $function_name: $count SVE math instructions"
    done
done
