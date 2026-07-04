#!/usr/bin/env kotlin
@file:CompilerOptions("-jvm-target", "17")

// Yumehiru TTS CLI — Zero dependencies, uses JDK built-in HTTP + espeak
// Usage: kotlin YumehiruCli.main.kts [command]
// Commands: status, tasks, alerts, speak <text>, watch, dashboard

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

val BASE = "http://127.0.0.1:18082"
val client = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(5))
    .build()

fun main(args: Array<String>) {
    val cmd = args.firstOrNull() ?: "dashboard"
    when (cmd) {
        "status" -> showStatus()
        "tasks" -> showTasks()
        "alerts" -> showAlerts()
        "speak" -> speak(args.drop(1).joinToString(" "))
        "watch" -> watchLoop()
        "dashboard" -> launchDashboard()
        else -> println("Commands: status, tasks, alerts, speak <text>, watch, dashboard")
    }
}

fun api(path: String): String {
    val req = HttpRequest.newBuilder(URI("$BASE$path")).GET().timeout(Duration.ofSeconds(10)).build()
    val resp = client.send(req, HttpResponse.BodyHandlers.ofString())
    return resp.body()
}

fun tts(text: String) {
    if (text.isBlank()) return
    val clean = text.replace(Regex("[^a-zA-Z0-9 .,!?;:'\"()\\-]"), " ").take(500)
    try {
        ProcessBuilder("espeak-ng", "-s", "175", "-p", "50", clean)
            .inheritIO().start().waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
    } catch (_: Exception) {}
}

fun showStatus() {
    val json = api("/api/status")
    // Parse minimal JSON manually (no deps)
    fun extract(key: String): String {
        val regex = Regex("\"$key\"\\s*:\\s*\"([^\"]+)\"")
        return regex.find(json)?.groupValues?.getOrNull(1) ?: "?"
    }
    println("╔══════════════════════════════╗")
    println("║   Yumehiru System Status     ║")
    println("╚══════════════════════════════╝")
    println("  llama-server: ${extract("llama-server")}")
    println("  tool-server:  ${extract("tool-server")}")
    println("  dashboard:    ${extract("dashboard")}")
    println("  Memory:       ${extract("memory")}")
    println("  Disk:         ${extract("disk")}")
    println("  Cron jobs:    ${extract("cron_jobs")}")
    println("  Uptime:       ${extract("uptime")}")
}

fun showTasks() {
    val json = api("/api/tasks")
    val taskRegex = Regex("\"id\"\\s*:\\s*(\\d+)[^}]*?\"title\"\\s*:\\s*\"([^\"]+)\"[^}]*?\"status\"\\s*:\\s*\"([^\"]+)\"[^}]*?\"priority\"\\s*:\\s*\"([^\"]+)\"")
    val matches = taskRegex.findAll(json)
    println("╔══════════════════════════════╗")
    println("║   Tasks                      ║")
    println("╚══════════════════════════════╝")
    var count = 0
    for (m in matches) {
        val (id, title, status, priority) = m.destructured
        val icon = when (status) { "active" -> "▶"; "pending" -> "○"; "done" -> "✓"; "blocked" -> "⛔"; else -> "?" }
        println("  $icon #$id [$status/$priority] $title")
        count++
    }
    if (count == 0) println("  (no tasks)")
}

fun showAlerts() {
    val json = api("/api/alerts")
    val alertRegex = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"[^}]*?\"type\"\\s*:\\s*\"([^\"]+)\"")
    val matches = alertRegex.findAll(json)
    println("╔══════════════════════════════╗")
    println("║   Alerts                     ║")
    println("╚══════════════════════════════╝")
    var count = 0
    for (m in matches) {
        val (msg, type) = m.destructured
        val icon = when (type) { "urgent" -> "🔴"; "blocked" -> "🟡"; else -> "⚪" }
        println("  $icon $msg")
        count++
    }
    if (count == 0) println("  ✨ All clear!")
}

fun speak(text: String) {
    if (text.isBlank()) {
        // Speak current status
        val tasks = api("/api/tasks")
        val active = Regex("\"status\"\\s*:\\s*\"active\"").findAll(tasks).count()
        val pending = Regex("\"status\"\\s*:\\s*\"pending\"").findAll(tasks).count()
        val msg = "Yumehiru system. $active active tasks, $pending pending tasks."
        println("🔊 $msg")
        tts(msg)
    } else {
        println("🔊 $text")
        tts(text)
    }
}

fun watchLoop() {
    println("👁 Watching for alerts (refresh every 15s)...")
    var lastAlertCount = 0
    while (true) {
        val json = api("/api/alerts")
        val count = Regex("\"type\"").findAll(json).count()
        if (count > lastAlertCount) {
            val alerts = api("/api/alerts")
            val msgRegex = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"")
            for (m in msgRegex.findAll(alerts)) {
                tts("Alert: ${m.groupValues[1]}")
            }
            lastAlertCount = count
        }
        // Also announce active task count
        val tasks = api("/api/tasks")
        val active = Regex("\"status\"\\s*:\\s*\"active\"").findAll(tasks).count()
        print("\r  👁 Watching | $count alerts | $active active tasks  ")
        Thread.sleep(15_000)
    }
}

fun launchDashboard() {
    println("""
╔══════════════════════════════════════════════╗
║   Yumehiru Voice Dashboard                   ║
║                                              ║
║   Commands:                                  ║
║     status   → System health                 ║
║     tasks    → List all tasks                ║
║     alerts   ║ Show current alerts           ║
║     speak    → Speak current status          ║
║     speak <text> → Speak custom text         ║
║     watch    → Live alert monitoring         ║
║                                              ║
║   Web UI: http://127.0.0.1:18082             ║
╚══════════════════════════════════════════════╝
    """.trimIndent())
}

main(args)
