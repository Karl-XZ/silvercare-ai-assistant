package com.silvercare.aiassistant;

/** Keeps queued work and delayed deliveries in the language generation that created them. */
final class GenerationGuard {
    interface CurrentGeneration { int get(); }

    private final CurrentGeneration current;
    private final int expected;

    GenerationGuard(CurrentGeneration current) {
        this.current = current;
        this.expected = current.get();
    }

    boolean isCurrent() { return expected == current.get(); }

    Runnable wrap(Runnable action) {
        return () -> { if (isCurrent()) action.run(); };
    }
}
