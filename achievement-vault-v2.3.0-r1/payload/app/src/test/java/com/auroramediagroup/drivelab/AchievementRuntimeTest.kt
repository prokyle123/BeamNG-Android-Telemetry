package com.auroramediagroup.drivelab

import org.junit.Assert.assertTrue
import org.junit.Test

class AchievementRuntimeTest {
    @Test
    fun reverseAndPedalChallengesAccumulateFromLiveFrames() {
        val runtime = AchievementRuntime()
        runtime.sync(DriverProgress(), AnalyzerState())

        repeat(20) { index ->
            runtime.update(
                frame = TelemetryFrame(
                    outGauge = OutGaugeData(
                        gearRaw = 0,
                        speedMps = 12.0,
                        rpm = 4_500.0,
                        throttle = 0.98,
                        brake = 0.40,
                        clutch = 0.30,
                        receivedAtMs = 1_000L + index * 500L
                    )
                ),
                analyzer = AnalyzerState(),
                dtSeconds = 0.5,
                redlineRpm = 7_000,
                driveActive = true
            )
        }

        val stats = runtime.snapshot()
        assertTrue((stats[AchievementMetric.REVERSE_SECONDS.name] ?: 0.0) >= 9.0)
        assertTrue((stats[AchievementMetric.MAX_REVERSE_SPEED_MPH.name] ?: 0.0) >= 25.0)
        assertTrue((stats[AchievementMetric.LONGEST_THROTTLE_BRAKE_SECONDS.name] ?: 0.0) >= 9.0)
        assertTrue((stats[AchievementMetric.LONGEST_ALL_PEDALS_SECONDS.name] ?: 0.0) >= 9.0)
    }

    @Test
    fun fullThrottleAndNoBrakeStreaksUseLivePacketTime() {
        val runtime = AchievementRuntime()
        runtime.sync(DriverProgress(), AnalyzerState())

        repeat(12) { index ->
            runtime.update(
                frame = TelemetryFrame(
                    outGauge = OutGaugeData(
                        gearRaw = 3,
                        speedMps = 20.0,
                        rpm = 5_000.0,
                        throttle = 0.98,
                        brake = 0.0,
                        receivedAtMs = 1_000L + index * 500L
                    )
                ),
                analyzer = AnalyzerState(),
                dtSeconds = 0.5,
                redlineRpm = 7_000,
                driveActive = true
            )
        }

        val stats = runtime.snapshot()
        assertTrue((stats[AchievementMetric.LONGEST_FULL_THROTTLE_SECONDS.name] ?: 0.0) >= 5.5)
        assertTrue((stats[AchievementMetric.LONGEST_NO_BRAKE_SECONDS.name] ?: 0.0) >= 5.5)
    }

    @Test
    fun defaultShiftScoreDoesNotCountBeforeAnyShift() {
        val runtime = AchievementRuntime()
        runtime.sync(DriverProgress(), AnalyzerState())
        runtime.update(
            frame = TelemetryFrame(outGauge = OutGaugeData(receivedAtMs = 1_000L)),
            analyzer = AnalyzerState(shift = ShiftMetrics(score = 100, totalShifts = 0)),
            dtSeconds = 0.5,
            redlineRpm = 7_000,
            driveActive = false
        )
        assertTrue((runtime.snapshot()[AchievementMetric.BEST_SHIFT_SCORE.name] ?: 0.0) == 0.0)
    }
}
