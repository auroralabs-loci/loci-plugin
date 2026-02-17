#include <iostream>
#include <chrono>

// Simple compute-intensive function to demonstrate optimization impact
long long fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

int main() {
    std::cout << "LOCI Build Configuration Example" << std::endl;
    std::cout << "=================================" << std::endl;
    std::cout << std::endl;

    // This computation will be MUCH faster with proper optimization flags
    // With -O0: ~5-10 seconds
    // With -O3: ~50-100 milliseconds (100x faster!)

    std::cout << "Computing fibonacci(35)..." << std::endl;

    auto start = std::chrono::high_resolution_clock::now();
    long long result = fibonacci(35);
    auto end = std::chrono::high_resolution_clock::now();

    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

    std::cout << "Result: " << result << std::endl;
    std::cout << "Time: " << duration.count() << " ms" << std::endl;
    std::cout << std::endl;

    // Print optimization level hint
    #ifdef NDEBUG
        std::cout << "Build: RELEASE (optimized)" << std::endl;
    #else
        std::cout << "Build: DEBUG (not optimized)" << std::endl;
    #endif

    std::cout << std::endl;
    std::cout << "LOCI Analysis:" << std::endl;
    std::cout << "- Captures the compilation flags used" << std::endl;
    std::cout << "- Compares -O0 vs -O3 performance impact" << std::endl;
    std::cout << "- Suggests optimization improvements" << std::endl;
    std::cout << "- Validates your build configuration" << std::endl;

    return 0;
}
