#include <vx_spawn2.h>
#include "common.h"

__kernel void kernel_main(kernel_arg_t* __UNIFORM__ arg) {
    auto src0 = reinterpret_cast<const TYPE*>(arg->src0_addr);
    auto src1 = reinterpret_cast<const TYPE*>(arg->src1_addr);
    auto dst = reinterpret_cast<TYPE*>(arg->dst_addr);
    const size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    // Put the two lane groups in separate cache lines for the -n8 probe.
    const size_t group_index = x / 2 + (x % 2) * (arg->dim_x / 2);
    const size_t start = group_index * arg->task_size;

    for (size_t i = 0; i < arg->task_size; ++i) {
        const size_t index = start + i;
        TYPE lhs, rhs, sum, zero;
        if (threadIdx.x & 1) {
            // A legal bypass should retain the odd lanes' mask.
            asm volatile(
                "lw %[lhs], 0(%[src0])\n\t"
                "lw %[rhs], 0(%[src1])\n\t"
                "add %[sum], %[lhs], %[rhs]\n\t"
                "xor %[zero], %[dst], %[dst]\n\t"
                "or %[sum], %[sum], %[zero]\n\t"
                "sw %[sum], 0(%[dst])"
                : [lhs] "=&r"(lhs), [rhs] "=&r"(rhs), [sum] "=&r"(sum),
                  [zero] "=&r"(zero)
                : [src0] "r"(src0 + index), [src1] "r"(src1 + index),
                  [dst] "r"(dst + index)
                : "memory");
        } else {
            // The independent xor may enter the buffer before the store issues.
            asm volatile(
                "lw %[lhs], 0(%[src0])\n\t"
                "lw %[rhs], 0(%[src1])\n\t"
                "add %[sum], %[lhs], %[rhs]\n\t"
                "sw %[sum], 0(%[dst])\n\t"
                "xor %[zero], %[dst], %[dst]\n\t"
                "or %[sum], %[sum], %[zero]\n\t"
                "sw %[sum], 0(%[dst])"
                : [lhs] "=&r"(lhs), [rhs] "=&r"(rhs), [sum] "=&r"(sum),
                  [zero] "=&r"(zero)
                : [src0] "r"(src0 + index), [src1] "r"(src1 + index),
                  [dst] "r"(dst + index)
                : "memory");
        }
    }
}
