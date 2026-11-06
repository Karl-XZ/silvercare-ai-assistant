package com.silvercare.aiassistant;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
import static org.junit.Assert.*;

public class GenerationGuardTest {
    @Test public void delayedOldResponseAndAlreadyPostedDeliveryAreDroppedAfterLanguageSwitch() throws Exception {
        AtomicInteger languageGeneration = new AtomicInteger();
        GenerationGuard oldLanguage = new GenerationGuard(languageGeneration::get);
        List<String> delivered = java.util.Collections.synchronizedList(new ArrayList<>());
        List<Runnable> uiQueue = java.util.Collections.synchronizedList(new ArrayList<>());
        uiQueue.add(oldLanguage.wrap(() -> delivered.add("already posted Chinese")));
        CountDownLatch inferenceStarted = new CountDownLatch(1);
        CountDownLatch finishInference = new CountDownLatch(1);
        Thread oldInference = new Thread(() -> {
            inferenceStarted.countDown();
            try { if (!finishInference.await(3, TimeUnit.SECONDS)) return; }
            catch (InterruptedException error) { Thread.currentThread().interrupt(); return; }
            oldLanguage.wrap(() -> uiQueue.add(oldLanguage.wrap(() -> delivered.add("late Chinese response")))).run();
        });
        oldInference.start();
        assertTrue(inferenceStarted.await(3, TimeUnit.SECONDS));
        languageGeneration.incrementAndGet();
        GenerationGuard currentLanguage = new GenerationGuard(languageGeneration::get);
        finishInference.countDown();
        oldInference.join(3000);
        assertFalse(oldInference.isAlive());
        uiQueue.add(currentLanguage.wrap(() -> delivered.add("English response")));
        for (Runnable delivery : uiQueue) delivery.run();
        assertEquals(java.util.List.of("English response"), delivered);
    }

    @Test public void queuedRequestDoesNotStartAfterItsLanguageWasReplaced() {
        AtomicInteger generation = new AtomicInteger();
        AtomicInteger starts = new AtomicInteger();
        GenerationGuard original = new GenerationGuard(generation::get);
        Runnable queuedRequest = original.wrap(starts::incrementAndGet);
        generation.incrementAndGet();
        queuedRequest.run();
        assertEquals(0, starts.get());
        new GenerationGuard(generation::get).wrap(starts::incrementAndGet).run();
        assertEquals(1, starts.get());
    }
}
