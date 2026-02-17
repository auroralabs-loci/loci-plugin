#include <vector>
#include <cstring>

// Abstract base class - virtual dispatch will happen here
class Entity {
public:
    virtual ~Entity() = default;
    virtual void update() = 0;
    virtual void render() {}

    float x, y, z;
    float vx, vy, vz;
};

// Concrete entity types
class Player : public Entity {
public:
    void update() override {
        x += vx;
        y += vy;
        z += vz;
        // Player-specific logic
    }
};

class Enemy : public Entity {
public:
    void update() override {
        x += vx;
        y += vy;
        z += vz;
        // Enemy AI logic
        vx += (rand() % 100 - 50) / 100.0f;
    }
};

// Global entity list
std::vector<Entity*> entities;

// ISSUE: Virtual dispatch in tight loop (1000+ times per frame)
// This function is performance-critical but uses virtual calls
void process_entities() {
    // Loop executes 1000+ times per frame in game loop
    // Virtual dispatch has overhead:
    // - Cache misses (vtable lookups)
    // - Branch misprediction (if-else in CPU pipeline)
    // - Inlining prevention

    for (size_t i = 0; i < entities.size(); i++) {
        entities[i]->update();  // LOCI DETECTS: Virtual dispatch in hot path
    }
}

// ANTI-PATTERN: Heap allocation in loop
void allocate_dynamic_entities(int count) {
    for (int i = 0; i < count; i++) {
        // Heap allocation causes:
        // - Cache thrashing
        // - Memory fragmentation
        // - Allocator overhead
        Entity* e = new Enemy();
        entities.push_back(e);  // LOCI DETECTS: Allocation in loop
    }
}

// ANTI-PATTERN: Large stack array
void process_batch() {
    // Stack arrays over ~10KB risk overflow
    float data[50000];  // LOCI DETECTS: Large stack array (200KB)
    memset(data, 0, sizeof(data));
}

// PERFORMANCE: std::endl flushes buffer
void log_entities() {
    for (const auto& e : entities) {
        // std::endl flushes, killing I/O throughput
        // Should use '\n' instead
    }
}

int main() {
    // Create some test entities
    for (int i = 0; i < 100; i++) {
        entities.push_back(new Player());
        entities.push_back(new Enemy());
    }

    // Main game loop
    for (int frame = 0; frame < 1000; frame++) {
        process_entities();  // Called every frame - LOCI tracks this
    }

    // Cleanup
    for (auto e : entities) {
        delete e;
    }

    return 0;
}
