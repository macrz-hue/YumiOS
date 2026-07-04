package yumehiru

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import java.io.File
import javax.swing.SwingUtilities

// ─── Theme Colors ─────────────────────────────────────────
val Purple = Color(0xFF7C5CFC)
val DarkBg = Color(0xFF0F0F14)
val DarkCard = Color(0xFF1A1A24)
val DarkBorder = Color(0xFF2A2A3A)
val TextLight = Color(0xFFE0E0E8)
val TextSubtle = Color(0xFF888888)
val Green = Color(0xFF44CC88)
val UrgentRed = Color(0xFFFF4444)
val Yellow = Color(0xFFFFCC44)
val Blue = Color(0xFF4488FF)

fun main() = application {
    var tasks by remember { mutableStateOf<List<Task>>(emptyList()) }
    var alerts by remember { mutableStateOf<List<Alert>>(emptyList()) }
    var status by remember { mutableStateOf<SystemStatus?>(null) }
    var selectedTab by remember { mutableStateOf(0) }
    var ttsEnabled by remember { mutableStateOf(true) }
    var previousAlertCount by remember { mutableStateOf(0) }
    var newTaskTitle by remember { mutableStateOf("") }
    var llmInput by remember { mutableStateOf("") }
    var llmOutput by remember { mutableStateOf("") }
    val api = remember { ApiClient() }
    val scope = rememberCoroutineScope()

    // Auto-refresh
    LaunchedEffect(Unit) {
        while (true) {
            api.getTasks().onSuccess { tasks = it }
            api.getAlerts().onSuccess { 
                alerts = it
                // Speak new alerts
                if (it.size > previousAlertCount && ttsEnabled) {
                    it.take(it.size - previousAlertCount).forEach { alert ->
                        scope.launch { TTS.speakAlert(alert) }
                    }
                }
                previousAlertCount = alerts.size
            }
            api.getStatus().onSuccess { status = it }
            delay(10_000)
        }
    }

    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Purple,
            background = DarkBg,
            surface = DarkCard,
            onPrimary = Color.White,
            onBackground = TextLight,
            onSurface = TextLight
        )
    ) {
        Window(
            onCloseRequest = ::exitApplication,
            title = "Yumehiru Dashboard 👻"
        ) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = DarkBg
            ) {
                Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
                    // Header
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("👻✨ Yumehiru", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("TTS", color = TextSubtle, fontSize = 12.sp)
                            Switch(
                                checked = ttsEnabled,
                                onCheckedChange = { 
                                    ttsEnabled = it
                                    TTS.setEnabled(it)
                                    if (it) scope.launch { TTS.speak("Voice alerts enabled") }
                                },
                                colors = SwitchDefaults.colors(checkedThumbColor = Purple)
                            )
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Tab Bar
                    val tabs = listOf("📋 Tasks", "🔔 Alerts", "📊 System", "🎤 Voice")
                    TabRow(
                        selectedTabIndex = selectedTab,
                        containerColor = DarkCard,
                        contentColor = Purple
                    ) {
                        tabs.forEachIndexed { i, label ->
                            Tab(
                                selected = selectedTab == i,
                                onClick = { selectedTab = i },
                                text = { Text(label, fontSize = 14.sp) }
                            )
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Content
                    when (selectedTab) {
                        0 -> TaskPanel(tasks, api, scope, ttsEnabled, ::refreshTasks, newTaskTitle, ::setNewTaskTitle)
                        1 -> AlertPanel(alerts, api, scope, ttsEnabled)
                        2 -> SystemPanel(status, api, scope, llmInput, ::setLlmInput, llmOutput, ::setLlmOutput)
                        3 -> VoicePanel(api, scope, ttsEnabled)
                    }
                }
            }
        }
    }
}

// ─── Refresh ─────────────────────────────────────────────
fun refreshTasks(api: ApiClient, tasks: MutableList<Task>, scope: CoroutineScope) {
    scope.launch {
        api.getTasks().onSuccess { tasks.clear(); tasks.addAll(it) }
    }
}

fun setNewTaskTitle(t: MutableState<String>, v: String) { t.value = v }
fun setLlmInput(t: MutableState<String>, v: String) { t.value = v }
fun setLlmOutput(t: MutableState<String>, v: String) { t.value = v }

// ─── Tabs ────────────────────────────────────────────────

@Composable
fun TaskPanel(
    tasks: List<Task>, api: ApiClient, scope: CoroutineScope, ttsEnabled: Boolean,
    onRefresh: () -> Unit, newTaskTitle: String, onTitleChange: (String) -> Unit
) {
    Column {
        // Status dots
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            val counts = mapOf(
                "pending" to tasks.count { it.status == "pending" },
                "active" to tasks.count { it.status == "active" },
                "blocked" to tasks.count { it.status == "blocked" },
                "done" to tasks.count { it.status == "done" }
            )
            counts.forEach { (k, v) ->
                val color = when (k) {
                    "pending" -> Blue; "active" -> Green; "blocked" -> UrgentRed; "done" -> Color(0xFF66AA66)
                    else -> TextSubtle
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Canvas(Modifier.size(8.dp)) { drawCircle(color) }
                    Spacer(Modifier.width(4.dp))
                    Text("$k $v", fontSize = 12.sp, color = TextSubtle)
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        // New task row
        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = newTaskTitle,
                onValueChange = onTitleChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("New task...", color = TextSubtle) },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Purple,
                    unfocusedBorderColor = DarkBorder
                )
            )
            Spacer(Modifier.width(8.dp))
            Button(
                onClick = {
                    if (newTaskTitle.isNotBlank()) {
                        scope.launch {
                            api.createTask(newTaskTitle)
                            onTitleChange("")
                            delay(500)
                            api.getTasks().onSuccess { /* refresh */ }
                        }
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = Purple)
            ) { Text("+") }
        }

        Spacer(Modifier.height(8.dp))

        // Task board columns
        Row(modifier = Modifier.fillMaxSize()) {
            listOf("pending", "active", "done").forEach { status ->
                val items = tasks.filter { it.status == status }
                    .sortedByDescending { if (it.priority == "high") 1 else if (it.priority == "medium") 0 else -1 }

                Column(modifier = Modifier.weight(1f).padding(4.dp)) {
                    Text(
                        status.uppercase(),
                        fontSize = 11.sp,
                        color = TextSubtle,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(bottom = 4.dp)
                    )

                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(items) { task ->
                            TaskCard(task, api, scope, ttsEnabled)
                            Spacer(Modifier.height(4.dp))
                        }
                        if (items.isEmpty()) {
                            item {
                                Text("—", color = TextSubtle, fontSize = 12.sp, modifier = Modifier.padding(8.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TaskCard(task: Task, api: ApiClient, scope: CoroutineScope, ttsEnabled: Boolean) {
    val bg = when (task.status) {
        "active" -> Color(0xFF0A1A10)
        "blocked" -> Color(0xFF1A0A0A)
        "done" -> Color(0xFF0A0A1A)
        else -> DarkCard
    }
    val border = when (task.status) {
        "active" -> Green; "blocked" -> UrgentRed; "done" -> Color(0xFF66AA66)
        else -> DarkBorder
    }

    Card(
        modifier = Modifier.fillMaxWidth().clickable { },
        colors = CardDefaults.cardColors(containerColor = bg),
        border = BorderStroke(1.dp, border)
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("#${task.id}", fontSize = 10.sp, color = Purple, fontWeight = FontWeight.Bold)
                Text(task.priority, fontSize = 10.sp, color = when (task.priority) {
                    "high" -> Yellow; "medium" -> Blue; else -> TextSubtle
                })
            }
            Text(
                task.title,
                fontSize = 13.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(vertical = 4.dp)
            )

            if (task.status != "done") {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    when (task.status) {
                        "pending" -> SmallButton("▶ Start") {
                            scope.launch {
                                api.updateTask(task.id, "start")
                                if (ttsEnabled) TTS.speakTaskStatus(task, "started")
                                delay(300)
                                api.getTasks().onSuccess { /* auto-refresh handles */ }
                            }
                        }
                        "active" -> SmallButton("✓ Done", Green) {
                            scope.launch {
                                api.updateTask(task.id, "done")
                                if (ttsEnabled) TTS.speakTaskStatus(task, "completed")
                                delay(300)
                            }
                        }
                        "blocked" -> SmallButton("↻ Unblock") {
                            scope.launch { api.updateTask(task.id, "unblock") }
                        }
                    }
                    if (task.status != "blocked") {
                        SmallButton("⛔", UrgentRed) {
                            scope.launch { api.updateTask(task.id, "block", "blocked manually") }
                        }
                    }
                }
            }

            if (task.blockedReason != null) {
                Text("⚠ ${task.blockedReason}", fontSize = 11.sp, color = Yellow, modifier = Modifier.padding(top = 4.dp))
            }
        }
    }
}

@Composable
fun SmallButton(text: String, color: Color = Purple, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = color),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
        shape = RoundedCornerShape(4.dp),
        modifier = Modifier.height(24.dp)
    ) {
        Text(text, fontSize = 10.sp)
    }
}

@Composable
fun AlertPanel(alerts: List<Alert>, api: ApiClient, scope: CoroutineScope, ttsEnabled: Boolean) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        if (alerts.isEmpty()) {
            item {
                Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text("✨ All clear! No alerts.", color = TextSubtle, fontSize = 16.sp)
                }
            }
        }
        items(alerts) { alert ->
            val color = when (alert.type) {
                "urgent" -> UrgentRed; "blocked" -> Yellow; else -> UrgentRed
            }
            val icon = when (alert.type) {
                "urgent" -> "🔴"; "blocked" -> "🟡"; else -> "🔴"
            }
            Card(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                colors = CardDefaults.cardColors(containerColor = DarkCard),
                border = BorderStroke(1.dp, color)
            ) {
                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(icon, fontSize = 18.sp)
                    Spacer(Modifier.width(8.dp))
                    Column {
                        Text(alert.message, fontSize = 13.sp, color = TextLight)
                        if (alert.reason != null) {
                            Text("Reason: ${alert.reason}", fontSize = 11.sp, color = TextSubtle)
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    SmallButton("Speak") {
                        scope.launch { TTS.speakAlert(alert) }
                    }
                }
            }
        }
    }
}

@Composable
fun SystemPanel(
    status: SystemStatus?, api: ApiClient, scope: CoroutineScope,
    llmInput: String, onLlmInput: (String) -> Unit,
    llmOutput: String, onLlmOutput: (String) -> Unit
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        item {
            // Services
            Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp), colors = CardDefaults.cardColors(containerColor = DarkCard)) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Services", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(4.dp))
                    status?.services?.let { s ->
                        listOf("llama-server" to s.`llama-server`, "tool-server" to s.`tool-server`, "dashboard" to s.dashboard).forEach { (name, st) ->
                            Row(modifier = Modifier.padding(vertical = 2.dp)) {
                                Canvas(Modifier.size(8.dp)) { drawCircle(if (st == "ok") Green else UrgentRed) }
                                Spacer(Modifier.width(6.dp))
                                Text("$name: $st", fontSize = 13.sp, color = TextLight)
                            }
                        }
                    }
                }
            }

            // Resources
            Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp), colors = CardDefaults.cardColors(containerColor = DarkCard)) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Resources", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("🧠 Memory: ${status?.memory ?: "..."}", fontSize = 13.sp)
                    Text("💾 Disk: ${status?.disk ?: "..."}", fontSize = 13.sp)
                    Text("🕐 ${status?.uptime ?: "..."}", fontSize = 13.sp)
                    Text("⏰ ${status?.cronJobs ?: 0} cron jobs", fontSize = 13.sp)
                }
            }

            // LLM Query
            Card(modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp), colors = CardDefaults.cardColors(containerColor = DarkCard)) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Ask Yumehiru", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Spacer(Modifier.height(4.dp))
                    OutlinedTextField(
                        value = llmInput,
                        onValueChange = onLlmInput,
                        modifier = Modifier.fillMaxWidth().height(60.dp),
                        placeholder = { Text("Ask anything...", color = TextSubtle) },
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Purple, unfocusedBorderColor = DarkBorder)
                    )
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                scope.launch {
                                    onLlmOutput("Thinking...")
                                    api.askLlm(llmInput).onSuccess { onLlmOutput(it) }.onFailure { onLlmOutput("Error: ${it.message}") }
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = Purple)
                        ) { Text("Ask") }
                        Button(
                            onClick = { if (llmOutput.isNotBlank()) scope.launch { TTS.speak(llmOutput) } },
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333344))
                        ) { Text("🔊 Speak") }
                    }
                    if (llmOutput.isNotBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(llmOutput, fontSize = 13.sp, color = TextLight)
                    }
                }
            }
        }
    }
}

@Composable
fun VoicePanel(api: ApiClient, scope: CoroutineScope, ttsEnabled: Boolean) {
    var textInput by remember { mutableStateOf("") }
    var statusText by remember { mutableStateOf("") }
    var rate by remember { mutableIntStateOf(175) }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // TTS Controls
        Card(colors = CardDefaults.cardColors(containerColor = DarkCard)) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Text-to-Speech", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = textInput,
                    onValueChange = { textInput = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Type something to speak...", color = TextSubtle) },
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Purple, unfocusedBorderColor = DarkBorder)
                )
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Speed:", fontSize = 12.sp, color = TextSubtle)
                    Slider(
                        value = rate.toFloat(),
                        onValueChange = { rate = it.toInt(); TTS.setRate(rate) },
                        valueRange = 80f..450f,
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                        colors = SliderDefaults.colors(thumbColor = Purple, activeTrackColor = Purple)
                    )
                    Text("$rate wpm", fontSize = 12.sp, color = TextSubtle)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { scope.launch { TTS.speak(textInput) } },
                        colors = ButtonDefaults.buttonColors(containerColor = Purple),
                        enabled = textInput.isNotBlank()
                    ) { Text("🔊 Speak") }
                    Button(
                        onClick = {
                            scope.launch {
                                api.getAlerts().onSuccess { alerts ->
                                    if (alerts.isNotEmpty()) {
                                        TTS.speak("You have ${alerts.size} alert${if (alerts.size > 1) "s" else ""}.")
                                        alerts.forEach { TTS.speakAlert(it) }
                                    } else {
                                        TTS.speak("No alerts. All clear.")
                                    }
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333344))
                    ) { Text("📢 Read Alerts") }
                    Button(
                        onClick = {
                            scope.launch {
                                api.getTasks().onSuccess { tasks ->
                                    val active = tasks.filter { it.status == "active" }
                                    val pending = tasks.filter { it.status == "pending" }
                                    val text = "Active: ${active.size} task${if (active.size != 1) "s" else ""}. Pending: ${pending.size}."
                                    TTS.speak(text)
                                    active.forEach { TTS.speakTaskStatus(it, "active") }
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333344))
                    ) { Text("📋 Read Tasks") }
                }
            }
        }

        // Status
        if (statusText.isNotBlank()) {
            Text(statusText, color = TextSubtle, fontSize = 12.sp)
        }

        Spacer(Modifier.weight(1f))

        // TTS File upload info
        Card(colors = CardDefaults.cardColors(containerColor = DarkCard)) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Speech Controls", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Spacer(Modifier.height(4.dp))
                Text("• Toggle voice alerts with the switch in the header.", fontSize = 12.sp, color = TextSubtle)
                Text("• Alerts are spoken automatically when they appear.", fontSize = 12.sp, color = TextSubtle)
                Text("• Use Read Alerts to hear current status.", fontSize = 12.sp, color = TextSubtle)
                Text("• Adjust speech speed with the slider.", fontSize = 12.sp, color = TextSubtle)
            }
        }
    }
}
