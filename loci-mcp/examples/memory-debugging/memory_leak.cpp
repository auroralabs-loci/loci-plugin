#include <iostream>
#include <vector>
#include <cstring>

// Example 1: Memory Leak
class ResourceWithLeak {
public:
    void allocate() {
        data = new int[1000];  // LOCI DETECTS: Allocation
    }
    // No destructor! Memory leak
private:
    int* data;
};

// Example 2: Use-After-Free
class RiskyPointer {
public:
    void cleanup() {
        delete ptr;  // Delete
        ptr = nullptr;  // Should do this always
    }

    void use() {
        if (ptr) {
            *ptr = 42;  // Potential use-after-free if cleanup was called
        }
    }

private:
    int* ptr;
};

// Example 3: Unsafe Cast
class UnsafeCastExample {
public:
    void dangerous_cast() {
        int i = 42;
        // LOCI DETECTS: reinterpret_cast used
        float* f = reinterpret_cast<float*>(&i);  // Unsafe!
        std::cout << *f << std::endl;
    }
};

// Example 4: Large Stack Array
void stack_overflow_risk() {
    // LOCI DETECTS: Large stack array (50000 * sizeof(float) = 200KB)
    // Stack is typically only 1-8MB, this is risky
    float data[50000];
    memset(data, 0, sizeof(data));
}

// Example 5: Unmatched Allocations
class LeakingContainer {
public:
    void add_item() {
        // Allocation in loop without cleanup
        items.push_back(new int(42));
        // LOCI DETECTS: Heap allocation in vector
    }

    void clear() {
        // Doesn't delete the pointed-to values!
        items.clear();  // Just clears pointers, memory still allocated
    }

    ~LeakingContainer() {
        // Should be:
        // for (auto p : items) delete p;
        // items.clear();
    }

private:
    std::vector<int*> items;
};

// Example 6: Double Delete
class DoubleDeleteBug {
public:
    DoubleDeleteBug() : data(new int[100]) {}

    // Copy constructor doesn't duplicate data
    DoubleDeleteBug(const DoubleDeleteBug& other) : data(other.data) {
        // Both point to same memory - double delete on destruction!
    }

    ~DoubleDeleteBug() {
        delete[] data;  // If copied, both destructors run
    }

private:
    int* data;
};

// Main demonstration
int main() {
    std::cout << "LOCI Memory Debugging Example" << std::endl;

    // Leak 1: Unreleased allocation
    {
        int* leak = new int(42);
        // Memory not freed - LOCI will detect this
    }

    // Leak 2: Vector of pointers
    {
        std::vector<int*> ptrs;
        for (int i = 0; i < 100; i++) {
            ptrs.push_back(new int(i));  // LOCI DETECTS: Allocation in loop
        }
        // Pointers deleted but not the allocated data
    }

    // Large allocation
    {
        char buffer[10000];  // LOCI DETECTS: Large stack array
        memset(buffer, 0, sizeof(buffer));
    }

    std::cout << "Program completed" << std::endl;
    return 0;
}
