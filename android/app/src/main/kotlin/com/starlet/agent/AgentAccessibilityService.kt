package com.starlet.agent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.hardware.HardwareBuffer
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream

class AgentAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AgentAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    private var cachedNodes: List<Map<String, Any?>> = emptyList()
    private var isCacheValid = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val type = event.eventType
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || 
            type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            type == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            isCacheValid = false
        }
        
        // Shadow Persona Messaging Proxy: Intercept WhatsApp/Telegram notifications
        if (type == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: ""
            if (packageName == "com.whatsapp" || packageName == "org.telegram.messenger") {
                val notificationText = event.text.joinToString(" ")
                // Draft response logic will be handled by the AI brain later
                println("Starlet Intercepted Message from \$packageName: \$notificationText")
            }
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    // ─── Screen Reading ──────────────────────────────────────────

    /** Dump the current screen as a flat list of UI elements */
    fun dumpScreen(): List<Map<String, Any?>> {
        if (isCacheValid && cachedNodes.isNotEmpty()) {
            return cachedNodes
        }
        val root = rootInActiveWindow ?: return emptyList()
        val nodes = mutableListOf<Map<String, Any?>>()
        traverseNode(root, nodes, 0)
        root.recycle()
        cachedNodes = nodes
        isCacheValid = true
        return nodes
    }

    private var cachedScreenDescription: String? = null

    /** High-Performance Native String-Builder Algorithm with Viewport Culling */
    fun getScreenDescriptionString(): String {
        if (isCacheValid && cachedScreenDescription != null) {
            return cachedScreenDescription!!
        }
        val root = rootInActiveWindow ?: return "Could not read screen. Accessibility root is null."
        val builder = StringBuilder()
        
        val pkg = root.packageName?.toString()
        if (pkg != null) {
            builder.append("Current app: ").append(pkg).append("\n")
        }
        builder.append("Screen elements:\n")
        
        var indexCounter = intArrayOf(0)
        traverseNodeForString(root, builder, 0, indexCounter)
        
        root.recycle()
        val result = builder.toString()
        cachedScreenDescription = result
        isCacheValid = true
        return result
    }

    private fun traverseNodeForString(
        node: AccessibilityNodeInfo,
        builder: StringBuilder,
        depth: Int,
        indexCounter: IntArray
    ) {
        // Viewport Culling Algorithm: Skip nodes that are entirely off-screen
        if (!node.isVisibleToUser) return

        val text = node.text?.toString() ?: ""
        val contentDesc = node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        
        val isClickable = node.isClickable
        val isEditable = node.isEditable
        val isScrollable = node.isScrollable

        val displayText = if (text.isNotEmpty()) text else contentDesc
        
        if (displayText.isNotEmpty() || isClickable || isEditable || isScrollable) {
            val currentIndex = indexCounter[0]++
            val tags = mutableListOf<String>()
            if (isClickable) tags.add("clickable")
            if (isEditable) tags.add("editable")
            if (isScrollable) tags.add("scrollable")

            val label = if (displayText.isNotEmpty()) "\"\$displayText\"" else "(no text)"
            val type = if (className.isNotEmpty()) "[\${className.substringAfterLast('.')}]" else ""
            val tagStr = if (tags.isNotEmpty()) "{\${tags.joinToString(\", \")}}" else ""
            
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val centerX = (rect.left + rect.right) / 2
            val centerY = (rect.top + rect.bottom) / 2
            val boundsStr = " bounds:[\${rect.left},\${rect.top},\${rect.right},\${rect.bottom}] center:(\$centerX,\$centerY)"
            
            builder.append("  [\$currentIndex] \$type \$label \$tagStr\$boundsStr\n")
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNodeForString(child, builder, depth + 1, indexCounter)
            child.recycle()
        }
    }

    private fun traverseNode(
        node: AccessibilityNodeInfo,
        nodes: MutableList<Map<String, Any?>>,
        depth: Int
    ) {
        val rect = Rect()
        node.getBoundsInScreen(rect)

        val text = node.text?.toString() ?: ""
        val contentDesc = node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        val viewId = node.viewIdResourceName ?: ""

        // Only include nodes that have text/description or are interactive
        if (text.isNotEmpty() || contentDesc.isNotEmpty() ||
            node.isClickable || node.isEditable || node.isScrollable
        ) {
            nodes.add(
                mapOf(
                    "index" to nodes.size,
                    "text" to text,
                    "contentDescription" to contentDesc,
                    "className" to className.substringAfterLast('.'),
                    "viewId" to viewId,
                    "isClickable" to node.isClickable,
                    "isEditable" to node.isEditable,
                    "isScrollable" to node.isScrollable,
                    "isCheckable" to node.isCheckable,
                    "isChecked" to node.isChecked,
                    "isFocused" to node.isFocused,
                    "bounds" to mapOf(
                        "left" to rect.left,
                        "top" to rect.top,
                        "right" to rect.right,
                        "bottom" to rect.bottom
                    ),
                    "depth" to depth
                )
            )
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, nodes, depth + 1)
            child.recycle()
        }
    }

    /** Capture screenshot as Base64 string */
    @RequiresApi(Build.VERSION_CODES.R)
    fun takeScreenshot(callback: (String?) -> Unit) {
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshotResult: ScreenshotResult) {
                    val hardwareBuffer = screenshotResult.hardwareBuffer
                    val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, screenshotResult.colorSpace)
                        ?.copy(Bitmap.Config.ARGB_8888, false)
                    
                    hardwareBuffer.close()

                    if (bitmap != null) {
                        // Native Zero-Copy Image Resizer: Downscale to 720p to save RAM and tokens
                        var finalBitmap = bitmap
                        var scaleFactor = 1.0f
                        if (bitmap.width > 720) {
                            scaleFactor = 720f / bitmap.width
                            val newHeight = (bitmap.height * scaleFactor).toInt()
                            finalBitmap = Bitmap.createScaledBitmap(bitmap, 720, newHeight, true)
                        }
                        
                        // Compress to lower quality JPEG to save bytes for the API
                        val byteArrayOutputStream = ByteArrayOutputStream()
                        finalBitmap.compress(Bitmap.CompressFormat.JPEG, 60, byteArrayOutputStream)
                        val byteArray = byteArrayOutputStream.toByteArray()
                        
                        // We append the scale factor at the start so Flutter knows how to scale taps back up
                        val base64String = "\$scaleFactor|" + Base64.encodeToString(byteArray, Base64.NO_WRAP)
                        callback(base64String)
                    } else {
                        callback(null)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    callback(null)
                }
            }
        )
    }

    // ─── Actions ─────────────────────────────────────────────────

    /** Invented Breakthrough: Fuzzy Semantic Interaction Engine (Self-Healing Clicks) */
    fun clickByText(targetText: String): Boolean {
        val root = rootInActiveWindow ?: return false
        var result = findAndClickNodeExact(root, targetText)
        if (!result) {
            // Self-healing fallback: Find best fuzzy match
            var bestMatch: AccessibilityNodeInfo? = null
            var bestScore = Int.MAX_VALUE
            
            fun fuzzySearch(node: AccessibilityNodeInfo) {
                val text = node.text?.toString() ?: ""
                val desc = node.contentDescription?.toString() ?: ""
                
                if (text.isNotEmpty() || desc.isNotEmpty()) {
                    val scoreText = if (text.isNotEmpty()) levenshtein(normalize(text), normalize(targetText)) else Int.MAX_VALUE
                    val scoreDesc = if (desc.isNotEmpty()) levenshtein(normalize(desc), normalize(targetText)) else Int.MAX_VALUE
                    val minScore = minOf(scoreText, scoreDesc)
                    
                    // Allow up to 30% error margin based on string length
                    val threshold = (targetText.length * 0.3).toInt().coerceAtLeast(1)
                    
                    if (minScore <= threshold && minScore < bestScore) {
                        bestScore = minScore
                        bestMatch = node
                    }
                }
                
                for (i in 0 until node.childCount) {
                    val child = node.getChild(i) ?: continue
                    fuzzySearch(child)
                }
            }
            
            fuzzySearch(root)
            
            if (bestMatch != null) {
                var clickTarget: AccessibilityNodeInfo? = bestMatch
                while (clickTarget != null && !clickTarget.isClickable) {
                    clickTarget = clickTarget.parent
                }
                if (clickTarget != null) {
                    result = clickTarget.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
            }
        }
        root.recycle()
        return result
    }

    private fun normalize(str: String): String {
        return str.replace(Regex("[^A-Za-z0-9]"), "").lowercase()
    }

    private fun levenshtein(lhs: CharSequence, rhs: CharSequence): Int {
        var cost = IntArray(lhs.length + 1) { it }
        var newCost = IntArray(lhs.length + 1)
        for (i in 1..rhs.length) {
            newCost[0] = i
            for (j in 1..lhs.length) {
                val match = if (lhs[j - 1] == rhs[i - 1]) 0 else 1
                val costReplace = cost[j - 1] + match
                val costInsert = cost[j] + 1
                val costDelete = newCost[j - 1] + 1
                newCost[j] = minOf(costInsert, costDelete, costReplace)
            }
            val swap = cost
            cost = newCost
            newCost = swap
        }
        return cost[lhs.length]
    }

    private fun findAndClickNodeExact(node: AccessibilityNodeInfo, targetText: String): Boolean {
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""

        if (text.equals(targetText, ignoreCase = true) ||
            desc.equals(targetText, ignoreCase = true) ||
            text.contains(targetText, ignoreCase = true) ||
            desc.contains(targetText, ignoreCase = true)
        ) {
            var clickTarget: AccessibilityNodeInfo? = node
            while (clickTarget != null && !clickTarget.isClickable) {
                clickTarget = clickTarget.parent
            }
            if (clickTarget != null) {
                return clickTarget.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (findAndClickNodeExact(child, targetText)) {
                return true
            }
        }
        return false
    }

    /** Click at specific coordinates using gesture */
    fun clickAtCoordinates(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Find an editable field (optionally by hint/nearby text) and type into it */
    fun typeText(text: String, fieldHint: String? = null): Boolean {
        val root = rootInActiveWindow ?: return false
        val editNode = findEditableNode(root, fieldHint)
        if (editNode != null) {
            editNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            val success = editNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            root.recycle()
            return success
        }
        root.recycle()
        return false
    }

    private fun findEditableNode(
        node: AccessibilityNodeInfo,
        hint: String?
    ): AccessibilityNodeInfo? {
        if (node.isEditable) {
            if (hint == null) return node
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            val hintText = node.hintText?.toString() ?: ""
            if (text.contains(hint, ignoreCase = true) ||
                desc.contains(hint, ignoreCase = true) ||
                hintText.contains(hint, ignoreCase = true)
            ) {
                return node
            }
            // If no hint match but this is the first editable, return it
            if (hint.isNullOrEmpty()) return node
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findEditableNode(child, hint)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    /** Scroll forward on the first scrollable element, or a specific one by text */
    fun scroll(direction: String, targetText: String? = null): Boolean {
        val root = rootInActiveWindow ?: return false
        val scrollNode = findScrollableNode(root, targetText)
        if (scrollNode != null) {
            val action = when (direction.lowercase()) {
                "down", "forward" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                "up", "backward" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                else -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            }
            val success = scrollNode.performAction(action)
            root.recycle()
            return success
        }
        root.recycle()
        return false
    }

    private fun findScrollableNode(
        node: AccessibilityNodeInfo,
        targetText: String?
    ): AccessibilityNodeInfo? {
        if (node.isScrollable) {
            if (targetText == null) return node
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (text.contains(targetText, ignoreCase = true) ||
                desc.contains(targetText, ignoreCase = true)
            ) {
                return node
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findScrollableNode(child, targetText)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    /** Press the global back button */
    fun pressBack(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_BACK)
    }

    /** Press the global home button */
    fun pressHome(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /** Open recent apps */
    fun openRecents(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_RECENTS)
    }

    /** Open notifications */
    fun openNotifications(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
    }

    /** Swipe gesture */
    fun swipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long = 300): Boolean {
        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Long press at coordinates */
    fun longPressAt(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1000))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /** Get the currently focused app's package name */
    fun getCurrentPackage(): String? {
        val root = rootInActiveWindow ?: return null
        val pkg = root.packageName?.toString()
        root.recycle()
        return pkg
    }
}
