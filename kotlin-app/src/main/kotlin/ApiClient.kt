package yumehiru

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

class ApiClient(private val baseUrl: String = "http://127.0.0.1:18082") {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) { json(json) }
    }

    suspend fun getTasks(): Result<List<Task>> = runCatching {
        val resp = client.get("$baseUrl/api/tasks")
        resp.body<TaskListResponse>().tasks
    }

    suspend fun getStatus(): Result<SystemStatus> = runCatching {
        client.get("$baseUrl/api/status").body<SystemStatus>()
    }

    suspend fun getAlerts(): Result<List<Alert>> = runCatching {
        client.get("$baseUrl/api/alerts").body<AlertResponse>().alerts
    }

    suspend fun getLogs(): Result<List<LogSource>> = runCatching {
        client.get("$baseUrl/api/logs").body<LogResponse>().logs
    }

    suspend fun updateTask(id: Int, action: String, reason: String? = null): Result<String> = runCatching {
        val body = buildMap {
            put("action", action)
            reason?.let { put("reason", it) }
        }
        val resp = client.put("$baseUrl/api/tasks/$id") {
            contentType(ContentType.Application.Json)
            setBody(body)
        }
        resp.body<TaskActionResponse>().result
    }

    suspend fun createTask(title: String, priority: String = "medium", tags: String = "manual"): Result<String> = runCatching {
        val resp = client.post("$baseUrl/api/tasks") {
            contentType(ContentType.Application.Json)
            setBody(mapOf("title" to title, "priority" to priority, "tags" to tags))
        }
        resp.body<TaskActionResponse>().result
    }

    suspend fun askLlm(prompt: String): Result<String> = runCatching {
        val resp = client.post("$baseUrl/api/llm") {
            contentType(ContentType.Application.Json)
            setBody(mapOf("prompt" to prompt))
        }
        resp.body<LlmResponse>().response
    }

    fun close() { client.close() }
}
