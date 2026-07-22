package com.auroramediagroup.drivelab

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AchievementCatalogTest {
    @Test
    fun catalogContainsExactly1001UniqueAchievements() {
        assertEquals(1001, AchievementCatalog.all.size)
        assertEquals(1001, AchievementCatalog.all.map { it.id }.toSet().size)
        assertEquals(1001, AchievementCatalog.all.map { it.title }.toSet().size)
        assertEquals(1000, AchievementCatalog.all.count { it.id != AchievementCatalog.MASTER_ID })
    }

    @Test
    fun everyRegularCategoryContainsOneHundredChallenges() {
        AchievementCategory.entries
            .filter { it != AchievementCategory.ALL }
            .forEach { category ->
                val expected = if (category == AchievementCategory.GENERAL) 101 else 100
                assertEquals(category.name, expected, AchievementCatalog.forCategory(category).size)
            }
    }

    @Test
    fun masterAchievementDoesNotUnlockEarly() {
        val progress = DriverProgress(
            achievements = AchievementCatalog.all
                .filter { it.id != AchievementCatalog.MASTER_ID }
                .take(999)
                .map { it.id }
                .toSet()
        )
        assertFalse(AchievementCatalog.MASTER_ID in AchievementCatalog.resolvedUnlocked(progress, progress.achievements))
    }

    @Test
    fun masterAchievementUnlocksAfterEveryRegularChallenge() {
        val regular = AchievementCatalog.all
            .filter { it.id != AchievementCatalog.MASTER_ID }
            .map { it.id }
            .toSet()
        val progress = DriverProgress(achievements = regular)
        assertTrue(AchievementCatalog.MASTER_ID in AchievementCatalog.resolvedUnlocked(progress, regular))
    }

    @Test
    fun originalDriverAcceptsLegacyProgress() {
        val progress = DriverProgress(legacyAchievementCount = 1)
        val unlocked = AchievementCatalog.resolvedUnlocked(progress, emptySet())
        assertTrue("GEN_09_00" in unlocked)
    }

    @Test
    fun lowerIsBetterGoalsDoNotUnlockFromMissingZeroValues() {
        val launchGoal = AchievementCatalog.all.first { achievement ->
            achievement.routes.flatten().any { it.metric == AchievementMetric.BEST_ZERO_TO_60_SECONDS }
        }
        assertFalse(launchGoal.unlocked(DriverProgress()))
    }

    @Test
    fun syntheticCompleteProgressReachesEveryCategoryAndMaster() {
        val stats = AchievementMetric.entries.associate { metric ->
            metric.name to if (metric.lowerIsBetter) 0.01 else 1_000_000.0
        }
        val progress = DriverProgress(
            totalXp = 100_000_000L,
            speedXp = 10_000_000L,
            driftXp = 10_000_000L,
            controlXp = 10_000_000L,
            enduranceXp = 10_000_000L,
            sessionsCompleted = 10_000,
            totalDistanceMeters = 100_000_000.0,
            totalDriveSeconds = 10_000_000.0,
            topSpeedMph = 500.0,
            bestDriftScore = 1_000_000,
            bestDriftAngleDeg = 90.0,
            cleanSessions = 10_000,
            totalShifts = 1_000_000,
            quarterMileRuns = 10_000,
            brakeRuns = 10_000,
            totalCrashes = 10_000,
            legacyAchievementCount = 500,
            achievementStats = stats
        )
        val unlocked = AchievementCatalog.resolvedUnlocked(progress, emptySet())
        assertEquals(1001, unlocked.size)
        assertTrue(AchievementCatalog.MASTER_ID in unlocked)
    }

    @Test
    fun vaultContainsSecretAndHighDifficultyGoals() {
        assertTrue(AchievementCatalog.all.count { it.secret } >= 40)
        assertTrue(AchievementCatalog.all.any { it.rarity == AchievementRarity.INSANE })
        assertTrue(AchievementCatalog.all.any { it.rarity == AchievementRarity.LEGENDARY })
    }
}
