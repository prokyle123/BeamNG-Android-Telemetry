package com.auroramediagroup.drivelab

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Bundle
import android.speech.tts.TextToSpeech
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.core.content.FileProvider
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

enum class DriveIntelligenceSensitivity(val label: String, val confidenceFloor: Double) {
    CONSERVATIVE("Conservative", 0.78),
    BALANCED("Balanced", 0.63),
    LOOSE("Loose", 0.50)
}

enum class DriveStoryDetail(val label: String, val maximumMoments: Int) {
    BRIEF("Brief", 3),
    NORMAL("Normal", 5),
    DETAILED("Detailed", 8)
}

enum class ManeuverType(val label: String, val spokenLabel: String, val baseXp: Int, val cooldownMs: Long) {
    DONUT("Donut", "Donut", 35, 8_000L),
    BURNOUT("Burnout", "Burnout", 20, 7_000L),
    J_TURN("J-turn", "J turn", 45, 8_000L),
    REVERSE_180("Reverse 180", "Reverse one eighty", 65, 10_000L),
    SCANDINAVIAN_FLICK("Scandinavian flick", "Scandinavian flick", 70, 8_000L),
    HANDBRAKE_TURN("Handbrake-style turn", "Handbrake turn", 45, 6_000L),
    DRIFT_TRANSITION("Drift transition", "Drift transition", 30, 2_000L),
    TWO_WHEEL("Two-wheel drive", "Two wheels", 75, 10_000L),
    WHEELIE("Wheelie", "Wheelie", 65, 9_000L),
    STOPPIE("Stoppie", "Stoppie", 65, 9_000L),
    BARREL_ROLL("Barrel roll", "Barrel roll", 150, 12_000L),
    BACKFLIP("Backflip", "Backflip", 165, 12_000L),
    FRONT_FLIP("Front flip", "Front flip", 165, 12_000L),
    FLAT_SPIN("Flat spin", "Flat spin", 145, 12_000L),
    CLEAN_JUMP("Clean jump", "Clean jump", 55, 4_000L),
    BIG_JUMP("Big jump", "Big jump", 100, 7_000L),
    HARD_LANDING("Hard landing", "Hard landing", 25, 4_000L),
    NEAR_ROLLOVER_RECOVERY("Near-rollover recovery", "Great save", 90, 10_000L),
    HIGH_SPEED_SAVE("High-speed save", "High speed save", 95, 8_000L)
}

data class ManeuverEvent(
    val id: String,
    val type: ManeuverType,
    val timestampMs: Long,
    val durationSeconds: Double,
    val speedMph: Double,
    val peakG: Double,
    val rotationDegrees: Double,
    val confidence: Double,
    val xp: Int,
    val detail: String,
    val isDemo: Boolean
)

data class DriverDnaProfile(
    val scores: Map<String, Double> = emptyMap(),
    val sessionsAnalyzed: Int = 0,
    val updatedAtMs: Long = 0L
) {
    val confidencePercent: Int get() = ((sessionsAnalyzed.coerceIn(0, 20) / 20.0) * 100.0).roundToInt()
    fun topTraits(count: Int = 3): List<Pair<String, Double>> =
        scores.entries.sortedByDescending { it.value }.take(count).map { it.key to it.value }
}

data class DriveStory(
    val title: String,
    val narrative: String,
    val moments: List<String>,
    val driverScore: Int,
    val dnaChanges: Map<String, Double> = emptyMap()
)

data class DriveIntelligenceRecord(
    val sessionId: String,
    val createdAtMs: Long,
    val events: List<ManeuverEvent>,
    val story: DriveStory?,
    val dnaBefore: DriverDnaProfile?,
    val dnaAfter: DriverDnaProfile?
)

data class DriveIntelligenceState(
    val currentEvent: ManeuverEvent? = null,
    val recentEvents: List<ManeuverEvent> = emptyList(),
    val dnaProfile: DriverDnaProfile = DriverDnaProfile()
)

val DriverDnaTraitLabels: Map<String, String> = linkedMapOf(
    "AGGRESSIVE" to "Aggressive",
    "PRECISE" to "Precise",
    "SMOOTH" to "Smooth",
    "FEARLESS" to "Fearless",
    "MECHANICAL" to "Mechanical",
    "DRIFT_FOCUSED" to "Drift-focused",
    "SPEED_FOCUSED" to "Speed-focused",
    "OFFROAD_SPECIALIST" to "Off-road specialist",
    "CLEAN_DRIVER" to "Clean driver",
    "CRASH_PRONE" to "Crash-prone",
    "LATE_BRAKER" to "Late braker",
    "MOMENTUM_DRIVER" to "Momentum driver"
)

private data class ManeuverCandidate(
    val type: ManeuverType,
    val confidence: Double,
    val durationSeconds: Double,
    val speedMph: Double,
    val peakG: Double,
    val rotationDegrees: Double,
    val detail: String
)

class DriveIntelligenceEngine(context: Context) {
    private val store = DriveIntelligenceStore(context.applicationContext)
    private val _state = MutableStateFlow(DriveIntelligenceState(dnaProfile = store.loadDna()))
    val state: StateFlow<DriveIntelligenceState> = _state.asStateFlow()

    private var lastPacketAtMs = 0L
    private var previousRollDeg: Double? = null
    private var previousPitchDeg: Double? = null
    private var previousYawDeg: Double? = null
    private var previousDriftSign = 0
    private var previousLateralSign = 0
    private var sessionActive = false
    private val sessionEvents = mutableListOf<ManeuverEvent>()
    private val sessionRepeatCounts = mutableMapOf<ManeuverType, Int>()
    private val lastEventTimes = mutableMapOf<ManeuverType, Long>()
    private var donutSeconds = 0.0
    private var donutLatched = false
    private var burnoutSeconds = 0.0
    private var burnoutLatched = false
    private var handbrakeSeconds = 0.0
    private var handbrakeLatched = false
    private var twoWheelSeconds = 0.0
    private var twoWheelLatched = false
    private var wheelieSeconds = 0.0
    private var wheelieLatched = false
    private var stoppieSeconds = 0.0
    private var stoppieLatched = false
    private var reverseArmed = false
    private var reverseYawDegrees = 0.0
    private var flickArmedAtMs = 0L
    private var saveArmed = false
    private var saveCrashId: String? = null
    private var rolloverRecoveryArmed = false
    private var rolloverPeakDegrees = 0.0
    private var rolloverCrashId: String? = null
    private var airborne = false
    private var airborneStartedAtMs = 0L
    private var airbornePeakSpeed = 0.0
    private var airborneRollDegrees = 0.0
    private var airbornePitchDegrees = 0.0
    private var airborneYawDegrees = 0.0

    fun loadRecords(): Map<String, DriveIntelligenceRecord> = store.loadRecords()
    fun deleteRecord(sessionId: String) = store.deleteRecord(sessionId)
    fun clearRecords() = store.clearRecords()
    fun resetDna() {
        store.resetDna()
        _state.value = _state.value.copy(dnaProfile = DriverDnaProfile())
    }
    fun dismissCurrentEvent() {
        _state.value = _state.value.copy(currentEvent = null)
    }

    fun update(frame: TelemetryFrame, analyzer: AnalyzerState, settings: AppSettings): ManeuverEvent? {
        val derived = frame.motionDerived ?: return null
        frame.motion ?: return null
        val now = maxOf(frame.outGauge?.receivedAtMs ?: 0L, frame.motion?.receivedAtMs ?: 0L)
            .takeIf { it > 0L } ?: System.currentTimeMillis()
        val dt = if (lastPacketAtMs <= 0L || now <= lastPacketAtMs) 0.0
            else ((now - lastPacketAtMs) / 1000.0).coerceIn(0.0, 0.25)
        lastPacketAtMs = now
        if (analyzer.recording && !sessionActive) {
            sessionActive = true
            sessionEvents.clear()
            sessionRepeatCounts.clear()
        }
        val roll = derived.rollDeg
        val pitch = derived.pitchDeg
        val yaw = derived.yawDeg
        val rollDelta = previousRollDeg?.let { wrappedAngleDelta(roll, it) } ?: 0.0
        val pitchDelta = previousPitchDeg?.let { wrappedAngleDelta(pitch, it) } ?: 0.0
        val yawDelta = previousYawDeg?.let { wrappedAngleDelta(yaw, it) } ?: 0.0
        val candidates = mutableListOf<ManeuverCandidate>()
        if (settings.stuntDetectionEnabled) {
            detectAirborne(frame, now, rollDelta, pitchDelta, yawDelta, candidates)
            detectGroundManeuvers(frame, analyzer, now, dt, yawDelta, settings, candidates)
        } else {
            resetTransientDetectors()
        }
        previousRollDeg = roll
        previousPitchDeg = pitch
        previousYawDeg = yaw
        val selected = candidates.filter { it.confidence >= settings.stuntSensitivity.confidenceFloor }
            .maxByOrNull { it.type.baseXp * it.confidence } ?: return null
        return emit(selected, now, frame.isDemo)
    }

    fun completeSession(
        session: SessionSummary,
        previousSession: SessionSummary?,
        settings: AppSettings,
        currentProgress: DriverProgress
    ): DriveIntelligenceRecord {
        val events = if (sessionEvents.isNotEmpty()) sessionEvents.toList() else
            _state.value.recentEvents.filter { it.timestampMs in session.startedAtMs..session.endedAtMs }.reversed()
        val dnaBefore = store.loadDna()
        val dnaAfter = if (settings.driverDnaEnabled) updateDna(dnaBefore, session, events) else dnaBefore
        if (settings.driverDnaEnabled) store.saveDna(dnaAfter)
        val story = if (settings.driveStoriesEnabled) {
            buildDriveStory(
                session,
                previousSession,
                events,
                settings,
                dnaBefore.takeIf { settings.driverDnaEnabled },
                dnaAfter.takeIf { settings.driverDnaEnabled },
                currentProgress
            )
        } else null
        val showDna = settings.driverDnaEnabled && settings.driverDnaShowAfterDrive
        val record = DriveIntelligenceRecord(
            session.id,
            System.currentTimeMillis(),
            events,
            story,
            dnaBefore.takeIf { showDna },
            dnaAfter.takeIf { showDna }
        )
        store.saveRecord(record)
        _state.value = _state.value.copy(dnaProfile = dnaAfter)
        sessionActive = false
        sessionEvents.clear()
        sessionRepeatCounts.clear()
        return record
    }

    private fun detectAirborne(
        frame: TelemetryFrame,
        now: Long,
        rollDelta: Double,
        pitchDelta: Double,
        yawDelta: Double,
        candidates: MutableList<ManeuverCandidate>
    ) {
        val derived = frame.motionDerived ?: return
        val speed = frame.speedMph
        val totalG = abs(derived.totalG)
        val verticalSpeed = abs(derived.verticalSpeedMps)
        val initialAirborne = speed >= 4.0 && totalG <= 0.55 && verticalSpeed >= 0.45
        if (!airborne && initialAirborne) {
            airborne = true
            airborneStartedAtMs = now
            airbornePeakSpeed = speed
            airborneRollDegrees = 0.0
            airbornePitchDegrees = 0.0
            airborneYawDegrees = 0.0
        }
        if (!airborne) return
        airbornePeakSpeed = max(airbornePeakSpeed, speed)
        airborneRollDegrees += rollDelta
        airbornePitchDegrees += pitchDelta
        airborneYawDegrees += yawDelta
        val duration = (now - airborneStartedAtMs) / 1000.0
        val landing = duration >= 0.25 && totalG >= 0.82
        if (!landing && duration < 12.0) return
        val absoluteRoll = abs(airborneRollDegrees)
        val absolutePitch = abs(airbornePitchDegrees)
        val absoluteYaw = abs(airborneYawDegrees)
        val type: ManeuverType?
        val rotation: Double
        when {
            absoluteRoll >= 260.0 -> { type = ManeuverType.BARREL_ROLL; rotation = absoluteRoll }
            absolutePitch >= 260.0 && airbornePitchDegrees > 0.0 -> { type = ManeuverType.BACKFLIP; rotation = absolutePitch }
            absolutePitch >= 260.0 -> { type = ManeuverType.FRONT_FLIP; rotation = absolutePitch }
            absoluteYaw >= 260.0 -> { type = ManeuverType.FLAT_SPIN; rotation = absoluteYaw }
            totalG >= 2.35 -> { type = ManeuverType.HARD_LANDING; rotation = max(absoluteRoll, absolutePitch) }
            duration >= 1.45 && totalG <= 1.95 -> { type = ManeuverType.BIG_JUMP; rotation = max(absoluteRoll, absolutePitch) }
            duration >= 0.42 && totalG <= 1.85 -> { type = ManeuverType.CLEAN_JUMP; rotation = max(absoluteRoll, absolutePitch) }
            else -> { type = null; rotation = 0.0 }
        }
        if (type != null) {
            val confidence = when (type) {
                ManeuverType.BARREL_ROLL,
                ManeuverType.BACKFLIP,
                ManeuverType.FRONT_FLIP,
                ManeuverType.FLAT_SPIN -> (0.72 + rotation / 1000.0).coerceIn(0.72, 0.98)
                ManeuverType.HARD_LANDING -> (0.60 + totalG / 10.0).coerceIn(0.60, 0.96)
                ManeuverType.BIG_JUMP -> (0.68 + duration / 10.0).coerceIn(0.68, 0.94)
                else -> (0.62 + duration / 8.0).coerceIn(0.62, 0.92)
            }
            candidates += ManeuverCandidate(
                type,
                confidence,
                duration,
                airbornePeakSpeed,
                totalG,
                rotation,
                when (type) {
                    ManeuverType.HARD_LANDING -> "${formatDi(totalG)} G landing after ${formatDi(duration)} seconds airborne"
                    ManeuverType.CLEAN_JUMP, ManeuverType.BIG_JUMP -> "${formatDi(duration)} seconds airborne with a ${formatDi(totalG)} G landing"
                    else -> "${rotation.roundToInt()} degrees of rotation over ${formatDi(duration)} seconds"
                }
            )
        }
        airborne = false
        airborneStartedAtMs = 0L
        airbornePeakSpeed = 0.0
        airborneRollDegrees = 0.0
        airbornePitchDegrees = 0.0
        airborneYawDegrees = 0.0
    }

    private fun detectGroundManeuvers(
        frame: TelemetryFrame,
        analyzer: AnalyzerState,
        now: Long,
        dt: Double,
        yawDelta: Double,
        settings: AppSettings,
        candidates: MutableList<ManeuverCandidate>
    ) {
        val out = frame.outGauge
        val derived = frame.motionDerived ?: return
        val speed = frame.speedMph
        val throttle = out?.throttle ?: 0.0
        val brake = out?.brake ?: 0.0
        val rpm = out?.rpm ?: 0.0
        val gearRaw = out?.gearRaw ?: 1
        val drift = derived.driftAngleDeg
        val absoluteDrift = abs(drift)
        val absoluteYawRate = abs(derived.yawRateDegPerSec)
        val roll = abs(derived.rollDeg)
        val pitch = abs(derived.pitchDeg)
        val totalG = abs(derived.totalG)
        val lateralSign = when {
            derived.lateralG > 0.12 -> 1
            derived.lateralG < -0.12 -> -1
            else -> 0
        }
        val driftSign = when {
            drift > 12.0 -> 1
            drift < -12.0 -> -1
            else -> 0
        }

        val donutCondition = speed in 3.0..23.0 && absoluteDrift >= 28.0 && absoluteYawRate >= 42.0 && throttle >= 0.35
        donutSeconds = if (donutCondition) donutSeconds + dt else 0.0
        if (donutSeconds >= 2.2 && !donutLatched) {
            candidates += ManeuverCandidate(ManeuverType.DONUT, (0.58 + donutSeconds / 8.0).coerceIn(0.58, 0.95), donutSeconds, speed, totalG, absoluteYawRate * donutSeconds, "${formatDi(donutSeconds)} seconds of sustained rotation")
            donutLatched = true
        }
        if (!donutCondition) donutLatched = false

        val burnoutCondition = speed <= 11.0 && throttle >= 0.76 && rpm >= settings.redlineRpm * 0.68 && absoluteYawRate <= 48.0
        burnoutSeconds = if (burnoutCondition) burnoutSeconds + dt else 0.0
        if (burnoutSeconds >= 1.15 && !burnoutLatched) {
            candidates += ManeuverCandidate(ManeuverType.BURNOUT, (0.53 + burnoutSeconds / 7.0).coerceIn(0.53, 0.90), burnoutSeconds, speed, totalG, 0.0, "${formatDi(burnoutSeconds)} seconds at high throttle and low road speed")
            burnoutLatched = true
        }
        if (!burnoutCondition) burnoutLatched = false

        val handbrakeCondition = speed >= 15.0 && brake >= 0.55 && throttle <= 0.38 && absoluteDrift >= 24.0 && absoluteYawRate >= 42.0
        handbrakeSeconds = if (handbrakeCondition) handbrakeSeconds + dt else 0.0
        if (handbrakeSeconds >= 0.42 && !handbrakeLatched) {
            candidates += ManeuverCandidate(ManeuverType.HANDBRAKE_TURN, (0.55 + brake * 0.25 + absoluteDrift / 300.0).coerceIn(0.55, 0.94), handbrakeSeconds, speed, totalG, absoluteYawRate * handbrakeSeconds, "${drift.roundToInt()}° rotation under heavy braking")
            handbrakeLatched = true
        }
        if (!handbrakeCondition) handbrakeLatched = false

        if (previousDriftSign != 0 && driftSign != 0 && previousDriftSign != driftSign && speed >= 20.0) {
            candidates += ManeuverCandidate(ManeuverType.DRIFT_TRANSITION, (0.62 + absoluteDrift / 250.0 + speed / 500.0).coerceIn(0.62, 0.96), 0.0, speed, totalG, absoluteDrift * 2.0, "Changed drift direction at ${speed.roundToInt()} MPH")
        }
        if (driftSign != 0) previousDriftSign = driftSign else if (absoluteDrift < 5.0) previousDriftSign = 0

        if (lateralSign != 0 && previousLateralSign != 0 && lateralSign != previousLateralSign && speed >= 28.0) flickArmedAtMs = now
        if (flickArmedAtMs > 0L && now - flickArmedAtMs <= 1_600L && absoluteDrift >= 18.0 && speed >= 28.0) {
            candidates += ManeuverCandidate(ManeuverType.SCANDINAVIAN_FLICK, (0.60 + absoluteDrift / 220.0 + abs(derived.lateralG) / 5.0).coerceIn(0.60, 0.96), (now - flickArmedAtMs) / 1000.0, speed, totalG, absoluteDrift, "Rapid weight transfer into a ${absoluteDrift.roundToInt()}° slide")
            flickArmedAtMs = 0L
        }
        if (flickArmedAtMs > 0L && now - flickArmedAtMs > 1_600L) flickArmedAtMs = 0L
        if (lateralSign != 0) previousLateralSign = lateralSign

        if (gearRaw == 0 && speed >= 7.0) {
            reverseArmed = true
            reverseYawDegrees += abs(yawDelta)
        } else if (reverseArmed && gearRaw >= 2) {
            val reverseType = when {
                reverseYawDegrees >= 135.0 -> ManeuverType.REVERSE_180
                reverseYawDegrees >= 65.0 -> ManeuverType.J_TURN
                else -> null
            }
            reverseType?.let {
                candidates += ManeuverCandidate(it, (0.58 + reverseYawDegrees / 500.0).coerceIn(0.58, 0.97), 0.0, speed, totalG, reverseYawDegrees, "${reverseYawDegrees.roundToInt()}° rotation from reverse into a forward gear")
            }
            reverseArmed = false
            reverseYawDegrees = 0.0
        } else if (reverseArmed && speed <= 1.5 && gearRaw != 0) {
            reverseArmed = false
            reverseYawDegrees = 0.0
        }

        val twoWheelCondition = !airborne && speed >= 10.0 && roll in 28.0..76.0 && totalG <= 2.2
        twoWheelSeconds = if (twoWheelCondition) twoWheelSeconds + dt else 0.0
        if (twoWheelSeconds >= 0.75 && !twoWheelLatched) {
            candidates += ManeuverCandidate(ManeuverType.TWO_WHEEL, (0.62 + twoWheelSeconds / 8.0 + roll / 500.0).coerceIn(0.62, 0.96), twoWheelSeconds, speed, totalG, roll, "${formatDi(twoWheelSeconds)} seconds at ${roll.roundToInt()}° of roll")
            twoWheelLatched = true
        }
        if (!twoWheelCondition) twoWheelLatched = false

        val wheelieCondition = !airborne && speed >= 8.0 && pitch >= 17.0 && throttle >= 0.58 && brake <= 0.12 && derived.longitudinalG >= 0.10
        wheelieSeconds = if (wheelieCondition) wheelieSeconds + dt else 0.0
        if (wheelieSeconds >= 0.60 && !wheelieLatched) {
            candidates += ManeuverCandidate(ManeuverType.WHEELIE, (0.60 + pitch / 250.0 + wheelieSeconds / 10.0).coerceIn(0.60, 0.94), wheelieSeconds, speed, totalG, pitch, "${formatDi(wheelieSeconds)} seconds at ${pitch.roundToInt()}° of pitch")
            wheelieLatched = true
        }
        if (!wheelieCondition) wheelieLatched = false

        val stoppieCondition = !airborne && speed >= 10.0 && pitch >= 14.0 && brake >= 0.63 && throttle <= 0.15
        stoppieSeconds = if (stoppieCondition) stoppieSeconds + dt else 0.0
        if (stoppieSeconds >= 0.50 && !stoppieLatched) {
            candidates += ManeuverCandidate(ManeuverType.STOPPIE, (0.58 + pitch / 260.0 + brake / 5.0).coerceIn(0.58, 0.94), stoppieSeconds, speed, totalG, pitch, "${formatDi(stoppieSeconds)} seconds under ${formatDi(abs(derived.longitudinalG))} longitudinal G")
            stoppieLatched = true
        }
        if (!stoppieCondition) stoppieLatched = false

        val crashId = analyzer.latestCrash?.id
        if (!saveArmed && speed >= 45.0 && absoluteDrift >= 38.0) {
            saveArmed = true
            saveCrashId = crashId
        }
        if (saveArmed && absoluteDrift <= 9.0 && speed >= 25.0) {
            if (crashId == saveCrashId) {
                candidates += ManeuverCandidate(ManeuverType.HIGH_SPEED_SAVE, (0.68 + speed / 500.0).coerceIn(0.68, 0.97), 0.0, speed, totalG, absoluteDrift, "Recovered control without an impact at ${speed.roundToInt()} MPH")
            }
            saveArmed = false
            saveCrashId = null
        }

        if (roll >= 55.0 && roll < 100.0 && !rolloverRecoveryArmed) {
            rolloverRecoveryArmed = true
            rolloverPeakDegrees = roll
            rolloverCrashId = crashId
        }
        if (rolloverRecoveryArmed) {
            rolloverPeakDegrees = max(rolloverPeakDegrees, roll)
            if (roll >= 100.0) {
                rolloverRecoveryArmed = false
            } else if (roll <= 20.0) {
                if (crashId == rolloverCrashId) {
                    candidates += ManeuverCandidate(ManeuverType.NEAR_ROLLOVER_RECOVERY, (0.68 + rolloverPeakDegrees / 400.0).coerceIn(0.68, 0.97), 0.0, speed, totalG, rolloverPeakDegrees, "Recovered from ${rolloverPeakDegrees.roundToInt()}° of roll without overturning")
                }
                rolloverRecoveryArmed = false
                rolloverPeakDegrees = 0.0
                rolloverCrashId = null
            }
        }
    }

    private fun emit(candidate: ManeuverCandidate, timestampMs: Long, isDemo: Boolean): ManeuverEvent? {
        val previous = lastEventTimes[candidate.type] ?: 0L
        if (timestampMs - previous < candidate.type.cooldownMs) return null
        lastEventTimes[candidate.type] = timestampMs
        val repeated = sessionRepeatCounts[candidate.type] ?: 0
        val repeatMultiplier = when (repeated) { 0 -> 1.0; 1 -> 0.65; 2 -> 0.38; else -> 0.18 }
        val xp = (candidate.type.baseXp * repeatMultiplier * candidate.confidence).roundToInt().coerceAtLeast(5)
        sessionRepeatCounts[candidate.type] = repeated + 1
        val event = ManeuverEvent(
            UUID.randomUUID().toString(), candidate.type, timestampMs, candidate.durationSeconds,
            candidate.speedMph, candidate.peakG, candidate.rotationDegrees, candidate.confidence,
            xp, candidate.detail, isDemo
        )
        if (sessionActive) sessionEvents += event
        _state.value = _state.value.copy(
            currentEvent = event,
            recentEvents = (listOf(event) + _state.value.recentEvents.filterNot { it.id == event.id }).take(30)
        )
        return event
    }

    private fun updateDna(previous: DriverDnaProfile, session: SessionSummary, events: List<ManeuverEvent>): DriverDnaProfile {
        val metrics = calculateDriveSessionMetrics(session)
        val samples = session.samples
        val averageThrottle = samples.map { it.throttle }.average().takeIf { it.isFinite() } ?: 0.0
        val averageBrake = samples.map { it.brake }.average().takeIf { it.isFinite() } ?: 0.0
        fun eventCount(vararg types: ManeuverType) = events.count { it.type in types }
        fun scaled(value: Double, maximum: Double) = (value / maximum * 100.0).coerceIn(0.0, 100.0)
        val cleanScore = (100 - session.crashCount * 28 - session.abuseScore / 2).coerceIn(0, 100).toDouble()
        val stuntIntensity = scaled(events.sumOf { it.type.baseXp }.toDouble(), 450.0)
        val jumpCount = eventCount(ManeuverType.CLEAN_JUMP, ManeuverType.BIG_JUMP, ManeuverType.HARD_LANDING, ManeuverType.BARREL_ROLL, ManeuverType.BACKFLIP, ManeuverType.FRONT_FLIP, ManeuverType.FLAT_SPIN)
        val driftEventCount = eventCount(ManeuverType.DONUT, ManeuverType.HANDBRAKE_TURN, ManeuverType.DRIFT_TRANSITION, ManeuverType.SCANDINAVIAN_FLICK, ManeuverType.HIGH_SPEED_SAVE)
        val raw = linkedMapOf(
            "AGGRESSIVE" to (averageThrottle * 52.0 + scaled(metrics.hardAccelerations.toDouble(), 12.0) * 0.20 + scaled(metrics.hardBrakingEvents.toDouble(), 10.0) * 0.15 + scaled(session.abuseScore.toDouble(), 100.0) * 0.13).coerceIn(0.0, 100.0),
            "PRECISE" to (metrics.driverScore * 0.42 + session.shiftScore * 0.36 + cleanScore * 0.22).coerceIn(0.0, 100.0),
            "SMOOTH" to (metrics.driverScore * 0.42 + (100 - session.abuseScore) * 0.28 + (100 - (metrics.hardAccelerations * 5 + metrics.hardBrakingEvents * 6).coerceIn(0, 100)) * 0.30).coerceIn(0.0, 100.0),
            "FEARLESS" to (scaled(session.maxSpeedMph, 170.0) * 0.42 + stuntIntensity * 0.40 + scaled(eventCount(ManeuverType.HIGH_SPEED_SAVE, ManeuverType.NEAR_ROLLOVER_RECOVERY).toDouble(), 4.0) * 0.18).coerceIn(0.0, 100.0),
            "MECHANICAL" to ((100 - session.abuseScore) * 0.55 + session.shiftScore * 0.45).coerceIn(0.0, 100.0),
            "DRIFT_FOCUSED" to (scaled(metrics.driftSeconds, 45.0) * 0.40 + scaled(session.driftScore.toDouble(), 25_000.0) * 0.35 + scaled(driftEventCount.toDouble(), 8.0) * 0.25).coerceIn(0.0, 100.0),
            "SPEED_FOCUSED" to (scaled(session.maxSpeedMph, 170.0) * 0.62 + scaled(metrics.averageSpeedMph, 80.0) * 0.38).coerceIn(0.0, 100.0),
            "OFFROAD_SPECIALIST" to (scaled(jumpCount.toDouble(), 7.0) * 0.58 + scaled(eventCount(ManeuverType.TWO_WHEEL, ManeuverType.NEAR_ROLLOVER_RECOVERY).toDouble(), 4.0) * 0.42).coerceIn(0.0, 100.0),
            "CLEAN_DRIVER" to cleanScore,
            "CRASH_PRONE" to (scaled(session.crashCount.toDouble(), 4.0) * 0.72 + scaled(eventCount(ManeuverType.HARD_LANDING).toDouble(), 3.0) * 0.28).coerceIn(0.0, 100.0),
            "LATE_BRAKER" to (scaled(metrics.hardBrakingEvents.toDouble(), 10.0) * 0.55 + averageBrake * 25.0 + if (session.sixtyToZeroSeconds != null || session.hundredToZeroSeconds != null) 20.0 else 0.0).coerceIn(0.0, 100.0),
            "MOMENTUM_DRIVER" to (scaled(metrics.averageSpeedMph, 75.0) * 0.46 + scaled(driftEventCount.toDouble(), 7.0) * 0.28 + (100 - scaled(metrics.hardBrakingEvents.toDouble(), 10.0)) * 0.26).coerceIn(0.0, 100.0)
        )
        val alpha = if (previous.sessionsAnalyzed <= 0) 1.0 else 0.14
        val smoothed = DriverDnaTraitLabels.keys.associateWith { key ->
            val old = previous.scores[key] ?: raw.getValue(key)
            old * (1.0 - alpha) + raw.getValue(key) * alpha
        }
        return DriverDnaProfile(smoothed, previous.sessionsAnalyzed + 1, System.currentTimeMillis())
    }

    private fun buildDriveStory(
        session: SessionSummary,
        previousSession: SessionSummary?,
        events: List<ManeuverEvent>,
        settings: AppSettings,
        dnaBefore: DriverDnaProfile?,
        dnaAfter: DriverDnaProfile?,
        currentProgress: DriverProgress
    ): DriveStory {
        val metrics = calculateDriveSessionMetrics(session)
        val moments = mutableListOf<Pair<Int, String>>()
        events.forEach { event -> moments += (event.type.baseXp + event.xp) to "${event.type.label}: ${event.detail} (+${event.xp} XP)" }
        if (previousSession != null) {
            if (session.maxSpeedMph > previousSession.maxSpeedMph + 1.0) moments += 180 to "Improved the previous drive's top speed by ${formatDi(session.maxSpeedMph - previousSession.maxSpeedMph)} MPH"
            val previousMetrics = calculateDriveSessionMetrics(previousSession)
            if (metrics.driverScore > previousMetrics.driverScore) moments += 170 to "Improved the driver score by ${metrics.driverScore - previousMetrics.driverScore} points"
            val currentZero = session.zeroTo60
            val previousZero = previousSession.zeroTo60
            if (currentZero != null && previousZero != null && currentZero < previousZero) moments += 190 to "Set a faster 0–60 result by ${formatDi(previousZero - currentZero)} seconds"
        }
        if (session.crashCount > 0 && settings.driveStoriesIncludeNegative) moments += 130 to "Survived ${session.crashCount} recorded impact${if (session.crashCount == 1) "" else "s"}"
        if (metrics.hardBrakingEvents > 0 && settings.driveStoriesIncludeNegative) moments += 90 to "Recorded ${metrics.hardBrakingEvents} hard braking event${if (metrics.hardBrakingEvents == 1) "" else "s"}"
        if (moments.isEmpty()) moments += 50 to "Completed the drive with a ${metrics.driverScore}/100 driver score"
        val selectedMoments = moments.sortedByDescending { it.first }.map { it.second }.distinct().take(settings.driveStoryDetail.maximumMoments)
        val dnaChanges = if (settings.driveStoriesIncludeDna && dnaBefore != null && dnaAfter != null) {
            DriverDnaTraitLabels.keys.associateWith { key -> (dnaAfter.scores[key] ?: 0.0) - (dnaBefore.scores[key] ?: 0.0) }.filterValues { abs(it) >= 0.5 }
        } else emptyMap()
        val topEvent = events.maxByOrNull { it.type.baseXp }
        val title = when {
            topEvent?.type in setOf(ManeuverType.BARREL_ROLL, ManeuverType.BACKFLIP, ManeuverType.FRONT_FLIP, ManeuverType.FLAT_SPIN) -> "Airborne chaos"
            events.any { it.type == ManeuverType.BIG_JUMP } -> "Big-air drive"
            events.any { it.type == ManeuverType.HIGH_SPEED_SAVE || it.type == ManeuverType.NEAR_ROLLOVER_RECOVERY } -> "Saved it"
            metrics.driftSeconds >= 10.0 -> "Sideways session"
            session.maxSpeedMph >= 120.0 -> "High-speed run"
            session.crashCount == 0 && session.abuseScore <= 20 -> "Clean drive"
            else -> "Drive complete"
        }
        val narrative = buildString {
            append("You drove ${formatDi(session.distanceMeters / 1609.344)} miles over ${formatDriveIntelligenceDuration(session.durationSeconds)} and reached ${session.maxSpeedMph.roundToInt()} MPH.")
            if (events.isNotEmpty()) append(" DriveLab detected ${events.size} maneuver${if (events.size == 1) "" else "s"}.")
            if (session.crashCount == 0) append(" The drive finished without a recorded impact.")
            else if (settings.driveStoriesIncludeNegative) append(" The black box recorded ${session.crashCount} impact${if (session.crashCount == 1) "" else "s"}.")
            append(" Driver score: ${metrics.driverScore}/100.")
            if (currentProgress.achievements.isNotEmpty()) append(" Achievement Vault progress remains active across the drive.")
        }
        return DriveStory(title, narrative, selectedMoments, metrics.driverScore, dnaChanges)
    }

    private fun resetTransientDetectors() {
        donutSeconds = 0.0; donutLatched = false
        burnoutSeconds = 0.0; burnoutLatched = false
        handbrakeSeconds = 0.0; handbrakeLatched = false
        twoWheelSeconds = 0.0; twoWheelLatched = false
        wheelieSeconds = 0.0; wheelieLatched = false
        stoppieSeconds = 0.0; stoppieLatched = false
        reverseArmed = false; reverseYawDegrees = 0.0
        flickArmedAtMs = 0L; saveArmed = false
        rolloverRecoveryArmed = false; airborne = false
    }
}

fun maneuverXpDelta(event: ManeuverEvent): LiveProgressDelta {
    val total = event.xp.coerceAtLeast(0)
    return when (event.type) {
        ManeuverType.DONUT, ManeuverType.BURNOUT, ManeuverType.HANDBRAKE_TURN, ManeuverType.DRIFT_TRANSITION -> LiveProgressDelta(driftXp = total)
        ManeuverType.SCANDINAVIAN_FLICK, ManeuverType.HIGH_SPEED_SAVE -> {
            val drift = (total * 0.55).roundToInt()
            LiveProgressDelta(driftXp = drift, controlXp = total - drift)
        }
        ManeuverType.J_TURN, ManeuverType.REVERSE_180, ManeuverType.NEAR_ROLLOVER_RECOVERY, ManeuverType.STOPPIE -> LiveProgressDelta(controlXp = total)
        ManeuverType.CLEAN_JUMP, ManeuverType.BIG_JUMP, ManeuverType.TWO_WHEEL, ManeuverType.WHEELIE -> {
            val endurance = (total * 0.55).roundToInt()
            LiveProgressDelta(enduranceXp = endurance, controlXp = total - endurance)
        }
        ManeuverType.BARREL_ROLL, ManeuverType.BACKFLIP, ManeuverType.FRONT_FLIP, ManeuverType.FLAT_SPIN -> {
            val endurance = (total * 0.45).roundToInt()
            LiveProgressDelta(enduranceXp = endurance, controlXp = total - endurance)
        }
        ManeuverType.HARD_LANDING -> LiveProgressDelta(enduranceXp = total)
    }
}

private class DriveIntelligenceStore(context: Context) {
    private val file = File(context.filesDir, "drive_intelligence.json")
    @Synchronized fun loadDna(): DriverDnaProfile = readRoot().optJSONObject("dna")?.let(::dnaFromJson) ?: DriverDnaProfile()
    @Synchronized fun saveDna(profile: DriverDnaProfile) { val root = readRoot(); root.put("dna", dnaToJson(profile)); writeRoot(root) }
    @Synchronized fun resetDna() = saveDna(DriverDnaProfile())
    @Synchronized fun loadRecords(): Map<String, DriveIntelligenceRecord> {
        val array = readRoot().optJSONArray("records") ?: JSONArray()
        return buildMap {
            for (index in 0 until array.length()) {
                val record = array.optJSONObject(index)?.let(::recordFromJson) ?: continue
                put(record.sessionId, record)
            }
        }
    }
    @Synchronized fun saveRecord(record: DriveIntelligenceRecord) {
        val combined = (listOf(record) + loadRecords().values.filterNot { it.sessionId == record.sessionId }).sortedByDescending { it.createdAtMs }.take(60)
        val root = readRoot()
        root.put("records", JSONArray().apply { combined.forEach { put(recordToJson(it)) } })
        writeRoot(root)
    }
    @Synchronized fun deleteRecord(sessionId: String) {
        val remaining = loadRecords().values.filterNot { it.sessionId == sessionId }
        val root = readRoot()
        root.put("records", JSONArray().apply { remaining.forEach { put(recordToJson(it)) } })
        writeRoot(root)
    }
    @Synchronized fun clearRecords() { val root = readRoot(); root.put("records", JSONArray()); writeRoot(root) }
    private fun readRoot(): JSONObject = if (!file.exists()) JSONObject() else runCatching { JSONObject(file.readText()) }.getOrDefault(JSONObject())
    private fun writeRoot(root: JSONObject) {
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(root.toString())
        if (!temporary.renameTo(file)) { file.writeText(root.toString()); temporary.delete() }
    }
    private fun eventToJson(event: ManeuverEvent) = JSONObject().apply {
        put("id", event.id); put("type", event.type.name); put("timestampMs", event.timestampMs)
        put("durationSeconds", event.durationSeconds); put("speedMph", event.speedMph); put("peakG", event.peakG)
        put("rotationDegrees", event.rotationDegrees); put("confidence", event.confidence); put("xp", event.xp)
        put("detail", event.detail); put("isDemo", event.isDemo)
    }
    private fun eventFromJson(json: JSONObject): ManeuverEvent? = runCatching {
        ManeuverEvent(
            json.getString("id"), ManeuverType.valueOf(json.getString("type")), json.getLong("timestampMs"),
            json.optDouble("durationSeconds", 0.0), json.optDouble("speedMph", 0.0), json.optDouble("peakG", 0.0),
            json.optDouble("rotationDegrees", 0.0), json.optDouble("confidence", 0.0), json.optInt("xp", 0),
            json.optString("detail"), json.optBoolean("isDemo", false)
        )
    }.getOrNull()
    private fun dnaToJson(dna: DriverDnaProfile) = JSONObject().apply {
        put("sessionsAnalyzed", dna.sessionsAnalyzed); put("updatedAtMs", dna.updatedAtMs)
        put("scores", JSONObject().apply { dna.scores.forEach { (key, value) -> put(key, value) } })
    }
    private fun dnaFromJson(json: JSONObject): DriverDnaProfile {
        val scoresJson = json.optJSONObject("scores") ?: JSONObject()
        val scores = buildMap {
            val keys = scoresJson.keys()
            while (keys.hasNext()) {
                val key = keys.next(); val value = scoresJson.optDouble(key, Double.NaN)
                if (value.isFinite()) put(key, value)
            }
        }
        return DriverDnaProfile(scores, json.optInt("sessionsAnalyzed", 0), json.optLong("updatedAtMs", 0L))
    }
    private fun storyToJson(story: DriveStory) = JSONObject().apply {
        put("title", story.title); put("narrative", story.narrative); put("driverScore", story.driverScore)
        put("moments", JSONArray().apply { story.moments.forEach(::put) })
        put("dnaChanges", JSONObject().apply { story.dnaChanges.forEach { (key, value) -> put(key, value) } })
    }
    private fun storyFromJson(json: JSONObject): DriveStory {
        val momentsJson = json.optJSONArray("moments") ?: JSONArray()
        val moments = buildList { for (index in 0 until momentsJson.length()) momentsJson.optString(index).takeIf { it.isNotBlank() }?.let(::add) }
        val changesJson = json.optJSONObject("dnaChanges") ?: JSONObject()
        val changes = buildMap {
            val keys = changesJson.keys()
            while (keys.hasNext()) {
                val key = keys.next(); val value = changesJson.optDouble(key, Double.NaN)
                if (value.isFinite()) put(key, value)
            }
        }
        return DriveStory(json.optString("title"), json.optString("narrative"), moments, json.optInt("driverScore", 0), changes)
    }
    private fun recordToJson(record: DriveIntelligenceRecord) = JSONObject().apply {
        put("sessionId", record.sessionId); put("createdAtMs", record.createdAtMs)
        put("events", JSONArray().apply { record.events.forEach { put(eventToJson(it)) } })
        put("story", record.story?.let(::storyToJson) ?: JSONObject.NULL)
        put("dnaBefore", record.dnaBefore?.let(::dnaToJson) ?: JSONObject.NULL)
        put("dnaAfter", record.dnaAfter?.let(::dnaToJson) ?: JSONObject.NULL)
    }
    private fun recordFromJson(json: JSONObject): DriveIntelligenceRecord? = runCatching {
        val eventsJson = json.optJSONArray("events") ?: JSONArray()
        val events = buildList { for (index in 0 until eventsJson.length()) eventsJson.optJSONObject(index)?.let(::eventFromJson)?.let(::add) }
        DriveIntelligenceRecord(
            json.getString("sessionId"), json.optLong("createdAtMs", 0L), events,
            if (json.isNull("story")) null else json.optJSONObject("story")?.let(::storyFromJson),
            if (json.isNull("dnaBefore")) null else json.optJSONObject("dnaBefore")?.let(::dnaFromJson),
            if (json.isNull("dnaAfter")) null else json.optJSONObject("dnaAfter")?.let(::dnaFromJson)
        )
    }.getOrNull()
}

@Composable
fun DriveIntelligenceEventHost(state: DriveIntelligenceState, settings: AppSettings, onDismiss: () -> Unit) {
    val event = state.currentEvent ?: return
    val context = LocalContext.current
    var textToSpeech by remember { mutableStateOf<TextToSpeech?>(null) }
    var ttsReady by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        var engine: TextToSpeech? = null
        engine = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                engine?.language = Locale.US
                engine?.setSpeechRate(1.03f)
                ttsReady = true
            }
        }
        textToSpeech = engine
        onDispose { engine?.stop(); engine?.shutdown(); textToSpeech = null; ttsReady = false }
    }
    LaunchedEffect(event.id) { delay(3_600L); onDismiss() }
    LaunchedEffect(event.id, settings.stuntSpeechEnabled, ttsReady) {
        if (settings.stuntSpeechEnabled && ttsReady) textToSpeech?.speak(event.type.spokenLabel, TextToSpeech.QUEUE_FLUSH, Bundle(), event.id)
    }
    if (!settings.stuntPopupsEnabled) return
    val color = maneuverColor(event.type)
    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.widthIn(max = 420.dp).fillMaxWidth().background(DrivePanel, RoundedCornerShape(24.dp))
                .border(2.dp, color.copy(alpha = 0.65f), RoundedCornerShape(24.dp)).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            Box(Modifier.size(52.dp).background(color.copy(alpha = 0.18f), CircleShape).border(2.dp, color, CircleShape), contentAlignment = Alignment.Center) {
                Text("DI", color = color, fontWeight = FontWeight.Black)
            }
            Text("MANEUVER DETECTED", color = DriveMuted, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelMedium)
            Text(event.type.label.uppercase(), color = color, fontWeight = FontWeight.Black, style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Text(event.detail, color = Color.White, textAlign = TextAlign.Center)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IntelligenceMetric("SPEED", "${event.speedMph.roundToInt()} MPH", Modifier.weight(1f))
                IntelligenceMetric("CONFIDENCE", "${(event.confidence * 100.0).roundToInt()}%", Modifier.weight(1f))
                IntelligenceMetric("REWARD", "+${event.xp} XP", Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun DriveIntelligenceSettingsCard(settings: AppSettings, fullEdition: Boolean, state: DriveIntelligenceState, viewModel: DriveLabViewModel) {
    Column(
        Modifier.fillMaxWidth().background(DrivePanel, RoundedCornerShape(18.dp))
            .border(1.dp, DriveCyan.copy(alpha = 0.25f), RoundedCornerShape(18.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("DRIVE INTELLIGENCE", color = DriveCyan, fontWeight = FontWeight.Black)
                Text("Stunt detection, optional Driver DNA, and locally generated Drive Stories.", color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            }
            Text(if (fullEdition) "FULL" else "LOCKED", color = if (fullEdition) DriveGreen else DriveAmber, fontWeight = FontWeight.Black)
        }
        IntelligenceToggle("Stunt and maneuver detection", "Detects donuts, burnouts, transitions, jumps, flips, two-wheel driving, recoveries, and other maneuvers.", settings.stuntDetectionEnabled && fullEdition, fullEdition, viewModel::setStuntDetectionEnabled)
        if (settings.stuntDetectionEnabled && fullEdition) {
            IntelligenceToggle("Large event popups", "Show a temporary event card when a maneuver is confirmed.", settings.stuntPopupsEnabled, true, viewModel::setStuntPopupsEnabled)
            IntelligenceToggle("Speak maneuver names", "Uses Android text-to-speech. Disabled by default.", settings.stuntSpeechEnabled, true, viewModel::setStuntSpeechEnabled)
            Text("DETECTION SENSITIVITY", color = DriveMuted, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                DriveIntelligenceSensitivity.entries.forEach { item ->
                    IntelligenceChoiceButton(item.label, settings.stuntSensitivity == item, Modifier.weight(1f)) { viewModel.setStuntSensitivity(item) }
                }
            }
        }
        IntelligenceToggle("Driver DNA", "Builds a slow-changing profile from completed drives. Off by default and stored only on this phone.", settings.driverDnaEnabled && fullEdition, fullEdition, viewModel::setDriverDnaEnabled)
        if (settings.driverDnaEnabled && fullEdition) {
            IntelligenceToggle("Show DNA changes after drives", "Include meaningful trait movement in the completed-drive summary.", settings.driverDnaShowAfterDrive, true, viewModel::setDriverDnaShowAfterDrive)
            Text("Profile evidence: ${state.dnaProfile.sessionsAnalyzed} completed drives • ${state.dnaProfile.confidencePercent}% confidence", color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            if (state.dnaProfile.sessionsAnalyzed > 0) OutlinedButton(onClick = viewModel::resetDriverDna, modifier = Modifier.fillMaxWidth()) { Text("RESET DRIVER DNA") }
        }
        IntelligenceToggle("Drive Stories", "Creates a local post-drive story using real session statistics and detected maneuvers.", settings.driveStoriesEnabled && fullEdition, fullEdition, viewModel::setDriveStoriesEnabled)
        if (settings.driveStoriesEnabled && fullEdition) {
            IntelligenceToggle("Include difficult moments", "Mention impacts and hard braking in the story.", settings.driveStoriesIncludeNegative, true, viewModel::setDriveStoriesIncludeNegative)
            IntelligenceToggle("Include Driver DNA movement", "Only applies when Driver DNA is enabled.", settings.driveStoriesIncludeDna, settings.driverDnaEnabled, viewModel::setDriveStoriesIncludeDna)
            Text("STORY DETAIL", color = DriveMuted, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                DriveStoryDetail.entries.forEach { item ->
                    IntelligenceChoiceButton(item.label, settings.driveStoryDetail == item, Modifier.weight(1f)) { viewModel.setDriveStoryDetail(item) }
                }
            }
        }
        if (!fullEdition) Text("Drive Intelligence is available with DriveLab Full. No Driver DNA information is collected while the feature is disabled.", color = DriveAmber, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun DriverDnaProgressCard(settings: AppSettings, state: DriveIntelligenceState) {
    val profile = state.dnaProfile
    Column(
        Modifier.fillMaxWidth().background(DrivePanel, RoundedCornerShape(20.dp))
            .border(1.dp, DriveCyan.copy(alpha = 0.22f), RoundedCornerShape(20.dp)).padding(15.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("DRIVER DNA", color = DriveCyan, fontWeight = FontWeight.Black)
            Text(if (settings.driverDnaEnabled) "${profile.confidencePercent}% CONFIDENCE" else "OFF", color = if (settings.driverDnaEnabled) DriveGreen else DriveMuted, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall)
        }
        if (!settings.driverDnaEnabled) {
            Text("Driver DNA is available but disabled by default. Enable it under Setup → Drive Intelligence to begin building a private driving profile.", color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            return@Column
        }
        if (profile.sessionsAnalyzed <= 0) {
            Text("Complete a recorded drive to begin building your profile. Trait scores change gradually instead of reacting to one isolated run.", color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            return@Column
        }
        profile.topTraits(3).forEach { (key, value) -> DriverDnaBar(DriverDnaTraitLabels[key] ?: key, value) }
        Text("${profile.sessionsAnalyzed} completed drives analyzed locally", color = DriveMuted, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun DriveStorySessionCard(session: SessionSummary, record: DriveIntelligenceRecord) {
    val story = record.story
    Column(
        Modifier.fillMaxWidth().background(DriveBackground.copy(alpha = 0.60f), RoundedCornerShape(14.dp))
            .border(1.dp, DriveCyan.copy(alpha = 0.18f), RoundedCornerShape(14.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("DRIVE STORY", color = DriveCyan, fontWeight = FontWeight.Black)
            if (record.events.isNotEmpty()) Text("${record.events.size} MANEUVERS", color = DriveAmber, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall)
        }
        if (story != null) {
            Text(story.title, color = Color.White, fontWeight = FontWeight.Bold)
            Text(story.narrative, color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            story.moments.take(5).forEach { Text("• $it", color = Color.White.copy(alpha = 0.86f), style = MaterialTheme.typography.bodySmall) }
        } else if (record.events.isNotEmpty()) {
            record.events.take(5).forEach { Text("• ${it.type.label}: ${it.detail}", color = DriveMuted, style = MaterialTheme.typography.bodySmall) }
        }
        Text(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAtMs)), color = DriveMuted, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
fun DriveStoryDialogCard(record: DriveIntelligenceRecord) {
    val story = record.story
    if (story == null && record.events.isEmpty()) return
    Column(
        Modifier.fillMaxWidth().background(DrivePanel2, RoundedCornerShape(14.dp))
            .border(1.dp, DriveCyan.copy(alpha = 0.22f), RoundedCornerShape(14.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text("DRIVE STORY", color = DriveCyan, fontWeight = FontWeight.Black)
        story?.let {
            Text(it.title, color = Color.White, fontWeight = FontWeight.Bold)
            Text(it.narrative, color = DriveMuted, style = MaterialTheme.typography.bodySmall)
            it.moments.take(5).forEach { moment -> Text("• $moment", color = Color.White.copy(alpha = 0.86f), style = MaterialTheme.typography.bodySmall) }
        }
    }
}

object DriveIntelligenceExport {
    fun shareStoryCard(context: Context, session: SessionSummary, record: DriveIntelligenceRecord) {
        val sharedDir = File(context.cacheDir, "shared").apply { mkdirs() }
        val file = File(sharedDir, "drivelab-story-${session.id.take(8)}.png")
        val bitmap = createStoryCard(session, record)
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, storyShareText(session, record))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Share DriveLab Drive Story"))
    }

    private fun createStoryCard(session: SessionSummary, record: DriveIntelligenceRecord): Bitmap {
        val width = 1080
        val height = 1350
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(android.graphics.Color.rgb(8, 12, 20))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.color = android.graphics.Color.rgb(0, 216, 255)
        paint.textSize = 66f
        canvas.drawText("DRIVELAB TELEM", 70f, 105f, paint)
        paint.color = android.graphics.Color.WHITE
        paint.textSize = 38f
        canvas.drawText("DRIVE STORY", 72f, 160f, paint)
        paint.color = android.graphics.Color.rgb(36, 44, 59)
        canvas.drawRoundRect(55f, 205f, 1025f, 1245f, 34f, 34f, paint)
        var y = 285f
        val story = record.story
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.color = android.graphics.Color.rgb(255, 202, 85)
        paint.textSize = 49f
        canvas.drawText(story?.title?.uppercase() ?: "DRIVE COMPLETE", 90f, y, paint)
        y += 72f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        paint.color = android.graphics.Color.WHITE
        paint.textSize = 30f
        y = drawWrappedText(canvas, story?.narrative ?: "DriveLab recorded this completed drive.", 90f, y, 900f, 40f, 7, paint)
        y += 22f
        val rows = listOf(
            "TOP SPEED" to "${formatDi(session.maxSpeedMph)} MPH",
            "DISTANCE" to "${formatDi(session.distanceMeters / 1609.344)} MI",
            "DRIVER SCORE" to "${story?.driverScore ?: calculateDriveSessionMetrics(session).driverScore}/100",
            "MANEUVERS" to record.events.size.toString(),
            "PEAK G" to "${formatDi(session.peakG)} G"
        )
        rows.forEach { (label, value) ->
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            paint.color = android.graphics.Color.rgb(172, 184, 203)
            paint.textSize = 28f
            canvas.drawText(label, 95f, y, paint)
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            paint.color = android.graphics.Color.WHITE
            paint.textSize = 38f
            canvas.drawText(value, 970f - paint.measureText(value), y, paint)
            y += 58f
        }
        y += 14f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.color = android.graphics.Color.rgb(0, 216, 255)
        paint.textSize = 29f
        canvas.drawText("MAJOR MOMENTS", 95f, y, paint)
        y += 43f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        paint.color = android.graphics.Color.WHITE
        paint.textSize = 25f
        (story?.moments ?: record.events.map { "${it.type.label}: ${it.detail}" }).take(4).forEach { moment ->
            y = drawWrappedText(canvas, "• $moment", 100f, y, 860f, 32f, 2, paint)
            y += 10f
        }
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        paint.color = android.graphics.Color.rgb(150, 161, 180)
        paint.textSize = 23f
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAtMs))
        canvas.drawText(date, 72f, 1300f, paint)
        val footer = "BeamNG.drive companion • DriveLab Telem"
        canvas.drawText(footer, width - 72f - paint.measureText(footer), 1300f, paint)
        return bitmap
    }

    private fun storyShareText(session: SessionSummary, record: DriveIntelligenceRecord): String = buildString {
        appendLine("DriveLab Telem Drive Story")
        record.story?.let {
            appendLine(it.title); appendLine(); appendLine(it.narrative)
            if (it.moments.isNotEmpty()) {
                appendLine(); appendLine("Major moments:")
                it.moments.forEach { moment -> appendLine("- $moment") }
            }
        }
        appendLine(); appendLine("Top speed: ${formatDi(session.maxSpeedMph)} MPH")
        appendLine("Distance: ${formatDi(session.distanceMeters / 1609.344)} mi")
        appendLine("Detected maneuvers: ${record.events.size}")
        append("Generated locally by DriveLab Telem.")
    }

    private fun drawWrappedText(
        canvas: Canvas,
        text: String,
        startX: Float,
        startY: Float,
        maximumWidth: Float,
        lineHeight: Float,
        maximumLines: Int,
        paint: Paint
    ): Float {
        val words = text.split(Regex("\\s+"))
        var line = ""
        var y = startY
        var lines = 0
        for (word in words) {
            val candidate = if (line.isBlank()) word else "$line $word"
            if (paint.measureText(candidate) <= maximumWidth) line = candidate
            else {
                canvas.drawText(line, startX, y, paint)
                y += lineHeight
                lines++
                if (lines >= maximumLines) return y
                line = word
            }
        }
        if (line.isNotBlank() && lines < maximumLines) {
            canvas.drawText(line, startX, y, paint)
            y += lineHeight
        }
        return y
    }
}

@Composable
private fun IntelligenceToggle(
    title: String,
    description: String,
    checked: Boolean,
    enabled: Boolean,
    onChecked: (Boolean) -> Unit
) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = if (enabled) Color.White else DriveMuted, fontWeight = FontWeight.Bold)
            Text(description, color = DriveMuted, style = MaterialTheme.typography.bodySmall)
        }
        Switch(checked = checked, enabled = enabled, onCheckedChange = onChecked)
    }
}

@Composable
private fun IntelligenceChoiceButton(text: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        border = BorderStroke(1.dp, if (selected) DriveCyan else Color.White.copy(alpha = 0.14f)),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = if (selected) DriveCyan.copy(alpha = 0.12f) else Color.Transparent,
            contentColor = if (selected) DriveCyan else DriveMuted
        )
    ) { Text(text, maxLines = 1, style = MaterialTheme.typography.labelSmall) }
}

@Composable
private fun DriverDnaBar(label: String, value: Double) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, color = Color.White, style = MaterialTheme.typography.bodySmall)
            Text(value.roundToInt().toString(), color = DriveCyan, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.bodySmall)
        }
        Box(Modifier.fillMaxWidth().height(8.dp).background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))) {
            Box(Modifier.fillMaxWidth((value / 100.0).coerceIn(0.0, 1.0).toFloat()).height(8.dp).background(DriveCyan, RoundedCornerShape(12.dp)))
        }
    }
}

@Composable
private fun IntelligenceMetric(label: String, value: String, modifier: Modifier) {
    Column(modifier.background(DrivePanel2, RoundedCornerShape(12.dp)).padding(horizontal = 7.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = DriveMuted, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
        Text(value, color = Color.White, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
    }
}

private fun maneuverColor(type: ManeuverType): Color = when (type) {
    ManeuverType.BARREL_ROLL, ManeuverType.BACKFLIP, ManeuverType.FRONT_FLIP, ManeuverType.FLAT_SPIN, ManeuverType.BIG_JUMP -> DriveAmber
    ManeuverType.HARD_LANDING -> DriveRed
    ManeuverType.CLEAN_JUMP, ManeuverType.HIGH_SPEED_SAVE, ManeuverType.NEAR_ROLLOVER_RECOVERY -> DriveGreen
    else -> DriveCyan
}

private fun wrappedAngleDelta(current: Double, previous: Double): Double {
    var delta = current - previous
    while (delta > 180.0) delta -= 360.0
    while (delta < -180.0) delta += 360.0
    return delta
}

private fun formatDi(value: Double): String = String.format(Locale.US, "%.1f", value)

private fun formatDriveIntelligenceDuration(seconds: Double): String {
    val safe = seconds.coerceAtLeast(0.0)
    val minutes = (safe / 60.0).toInt()
    val remaining = (safe - minutes * 60).roundToInt()
    return if (minutes > 0) "$minutes min $remaining sec" else "$remaining sec"
}
