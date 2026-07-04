package yumehiru

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Task(
    val id: Int = 0,
    val title: String = "",
    val status: String = "pending",
    val priority: String = "medium",
    val created: String = "",
    val updated: String = "",
    val source: String = "",
    val tags: List<String> = emptyList(),
    val notes: String = "",
    @SerialName("blocked_reason") val blockedReason: String? = null
)

@Serializable
data class TaskListResponse(val tasks: List<Task> = emptyList())

@Serializable
data class ServiceStatus(val `llama-server`: String = "unknown", val `tool-server`: String = "unknown", val dashboard: String = "unknown")

@Serializable
data class SystemStatus(
    val services: ServiceStatus = ServiceStatus(),
    @SerialName("cron_jobs") val cronJobs: Int = 0,
    val memory: String = "",
    val disk: String = "",
    val uptime: String = ""
)

@Serializable
data class Alert(
    val type: String = "",
    @SerialName("task_id") val taskId: Int? = null,
    val message: String = "",
    val status: String = "",
    val reason: String? = null
)

@Serializable
data class AlertResponse(val alerts: List<Alert> = emptyList())

@Serializable
data class LlmResponse(val response: String = "", val error: String? = null)

@Serializable
data class TaskActionResponse(val result: String = "", val error: String? = null)

@Serializable
data class UploadResponse(
    val filename: String = "",
    val url: String = "",
    @SerialName("ocr_text") val ocrText: String = "",
    val analysis: String = ""
)

@Serializable
data class LogSource(val source: String = "", val lines: List<String> = emptyList())

@Serializable
data class LogResponse(val logs: List<LogSource> = emptyList())
