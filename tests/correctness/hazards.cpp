#include <vx_spawn2.h>
#include "common.h"

__kernel void kernel_main(kernel_arg_t* __UNIFORM__ arg) {
    auto src0 = reinterpret_cast<const TYPE*>(arg->src0_addr);
    auto src1 = reinterpret_cast<const TYPE*>(arg->src1_addr);
    auto dst = reinterpret_cast<TYPE*>(arg->dst_addr);
    const size_t gx = blockIdx.x * blockDim.x + threadIdx.x;
    const size_t gy = blockIdx.y * blockDim.y + threadIdx.y;
    const size_t start = (gy * arg->dim_x + gx) * arg->task_size;

    for (size_t i = 0; i < arg->task_size; ++i) {
        const size_t index = start + i;
        const TYPE rhs = src1[index];
        const TYPE* input = src0 + index;
        TYPE lhs, raw_old, raw, war_rhs, war, scratch, waw;

        // The three result registers must each hold lhs + rhs.
        asm volatile(
            "lw %[lhs], 0(%[input])\n\t"
            "add %[raw_old], %[lhs], %[rhs]\n\t"
            "mv %[raw], %[raw_old]\n\t"
            "mv %[war_rhs], %[rhs]\n\t"
            "lw %[lhs], 0(%[input])\n\t"
            "add %[war], %[lhs], %[war_rhs]\n\t"
            "li %[war_rhs], 0\n\t"
            "lw %[lhs], 0(%[input])\n\t"
            "addi %[scratch], %[lhs], 1\n\t"
            "mv %[scratch], %[rhs]\n\t"
            "add %[waw], %[lhs], %[scratch]"
            : [lhs] "=&r"(lhs), [raw_old] "=&r"(raw_old), [raw] "=&r"(raw),
              [war_rhs] "=&r"(war_rhs), [war] "=&r"(war),
              [scratch] "=&r"(scratch), [waw] "=&r"(waw)
            : [input] "r"(input), [rhs] "r"(rhs)
            : "memory");
        dst[index] = raw ^ war ^ waw;
    }
}
