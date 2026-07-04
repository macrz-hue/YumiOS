package yumehiru

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Text-to-Speech using espeak-ng via shell.
 * Falls back silently if espeak is not available.
 */
object TTS {
    private var enabled = true
    private var rate = 175  // words per minute

    fun setEnabled(v: Boolean) { enabled = v }
    fun isEnabled() = enabled
    fun setRate(r: Int) { rate = r.coerceIn(80, 450) }

    suspend fun speak(text: String) = withContext(Dispatchers.IO) {
        if (!enabled || text.isBlank()) return@withContext
        try {
            // Sanitize: keep alphanumeric, punctuation, spaces
            val clean = text.replace(Regex("[^a-zA-Z0-9 .,!?;:'\"()\\-]"), " ")
            val proc = ProcessBuilder(
                "espeak-ng", "-s", rate.toString(), "-p", "50", clean
            ).inheritIO().start()
            proc.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: Exception) { /* silent fallback */ }
    }

    suspend fun speakAlert(alert: Alert) {
        val msg = when (alert.type) {
            "urgent" -> "Urgent: ${alert.message}"
            "blocked" -> "Blocked: ${alert.message}"
            "error" -> "Error: ${alert.message}"
            else -> "Alert: ${alert.message}"
        }
        speak(msg)
    }

    suspend fun speakTaskStatus(task: Task, action: String) {
        speak("Task $action: ${task.title}")
    }
}
