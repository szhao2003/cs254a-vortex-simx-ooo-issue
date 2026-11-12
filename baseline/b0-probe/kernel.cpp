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
        TYPE lhs, rhs, sum;
        TYPE* address;
        // Keep the independent address calculation after the load consumer.
        asm volatile(
            "lw %[lhs], 0(%[src0])\n\t"
            "lw %[rhs], 0(%[src1])\n\t"
            "add %[sum], %[lhs], %[rhs]\n\t"
            "add %[address], %[dst], %[offset]\n\t"
            "sw %[sum], 0(%[address])"
            : [lhs] "=&r"(lhs), [rhs] "=&r"(rhs), [sum] "=&r"(sum),
              [address] "=&r"(address)
            : [src0] "r"(src0 + index), [src1] "r"(src1 + index),
              [dst] "r"(dst), [offset] "r"(index * sizeof(TYPE))
            : "memory");
    }
}
