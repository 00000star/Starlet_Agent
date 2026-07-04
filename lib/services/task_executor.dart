import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'ai_service.dart';
import 'screen_automation_service.dart';
import 'app_launcher_service.dart';
import 'notification_service.dart';
import 'shizuku_service.dart';

/// Executes multi-step UI automation tasks using LLM-guided screen reading.
/// Incorporates Vision Fallback and RAM optimization (Sliding Window Scratchpad).
class TaskExecutor {
  final AiService _aiService;
  final ScreenAutomationService _screenService;
  final AppLauncherService _appLauncher;
  final ShizukuService _shizukuService;
  final NotificationService _notificationService = NotificationService();

  static bool isHalted = false;

  final void Function(String message)? onProgress;

  // State Summarization Scratchpad to remember past steps (Sliding window for 4GB RAM)
  final List<String> _scratchpad = [];

  TaskExecutor({
    required AiService aiService,
    required ScreenAutomationService screenService,
    required AppLauncherService appLauncher,
    required ShizukuService shizukuService,
    this.onProgress,
  })  : _aiService = aiService,
        _screenService = screenService,
        _appLauncher = appLauncher,
        _shizukuService = shizukuService;

  static const String _taskSystemPrompt = '''
You are a phone automation agent. You are given a TASK and the current SCREEN content.
You must decide what single action to take next to accomplish the task.
You have a scratchpad of past actions to avoid repeating mistakes or looping.
If the screen state is identical to the previous step, you must rely on Pure AI Inference to realize you are stuck and try a different approach.

Respond with ONLY a JSON object (no markdown, no code fences):
{
  "action": "action_name",
  "params": {"key": "value"},
  "reasoning": "why you chose this action",
  "is_complete": false
}

Available actions:
- click_text: {"text": "exact text to click"} - Click an element by its visible text
- click_at: {"x": 540, "y": 960} - Click at screen coordinates (use center coordinates from screen dump)
- type_text: {"text": "hello", "field_hint": "optional hint"} - Type into the focused/first edit field
- scroll: {"direction": "down"} - Scroll down/up on the current view
- press_back: {} - Press the back button
- press_home: {} - Press the home button
- open_app: {"app_name": "WhatsApp"} - Open an app
- wait: {} - Wait a moment for content to load
- request_vision: {} - Use vision fallback if the screen dump is missing elements
- done: {} - Task is complete

Rules:
- You will receive a TEXT DUMP of the accessibility tree containing exact text strings and center coordinates.
- ALWAYS use the text dump to decide your next action.
- If you need to click something, prefer using `click_text`. If the element does not have text, use `click_at` with the coordinates provided in the text dump.
- When typing in a search box, you MUST click it first, wait a step, and THEN type.
- Set is_complete=true ONLY when the task is fully done.
- If you need to find something by scrolling, scroll and then check the screen again.
- Keep reasoning very brief (1 sentence)
''';

  Future<String> executeTask(String userGoal) async {
    final isRunning = await _screenService.isServiceRunning();
    if (!isRunning) {
      return 'Accessibility service is not enabled. Go to Settings → Accessibility → PrivateAgent Screen Control and enable it.';
    }

    final results = <String>[];
    results.add('Starting task: $userGoal');
    _report('Starting task: $userGoal');
    _scratchpad.clear();
    isHalted = false;

    for (int step = 0; step < _aiService.maxSteps; step++) {
      if (isHalted) {
        results.add('Task halted by user.');
        _report('Task halted by user.');
        _notificationService.showTaskCompleteNotification('Task Halted', 'Emergency halt triggered.');
        return results.join('\n');
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // 1. Read the current screen text
      final screenContent = await _screenService.getScreenDescription();
      developer.log('=== SCREEN DUMP (Step ${step + 1}) ===\n$screenContent', name: 'PrivateAgent');

      // 2. Ask LLM what to do next
      final prompt = '''TASK: $userGoal

PAST ACTIONS SCRATCHPAD:
${_scratchpad.join('\n')}

CURRENT SCREEN TEXT DUMP:
$screenContent

Step ${step + 1}/${_aiService.maxSteps}. Look at the text dump and coordinates. What is the next action?''';

      developer.log('=== AI PROMPT ===\n$prompt', name: 'PrivateAgent');

      String response;
      try {
        // Use stateless message to prevent OOM
        response = await _aiService.sendStatelessMessage(prompt, systemOverride: _taskSystemPrompt);
        developer.log('=== RAW AI RESPONSE ===\n$response', name: 'PrivateAgent');
      } catch (e) {
        results.add('AI error: $e');
        _report('Error: $e');
        _notificationService.showTaskCompleteNotification('Task Error', 'AI encountered an error.');
        return results.join('\n');
      }

      // 3. Parse the action
      Map<String, dynamic>? actionJson;
      try {
        String jsonStr = response.trim();
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(0)!;
        }
        actionJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        results.add('Step ${step + 1}: Invalid JSON response');
        _report('Error: AI did not return valid JSON code.');
        _notificationService.showTaskCompleteNotification('Task Error', 'AI formatting error.');
        return results.join('\n');
      }

      final action = actionJson['action'] as String? ?? 'done';
      final params = actionJson['params'] as Map<String, dynamic>? ?? {};
      final reasoning = actionJson['reasoning'] as String? ?? '';
      final isComplete = actionJson['is_complete'] == true;

      developer.log('=== PARSED ACTION ===\nAction: $action\nParams: $params\nReasoning: $reasoning\nIs Complete: $isComplete', name: 'PrivateAgent');
      _report('Step ${step + 1}: $reasoning');

      // 4. Execute the action
      bool success = false;
      String actionResult = '';

      switch (action) {
        case 'click_text':
          final text = params['text'] as String? ?? '';
          success = await _screenService.clickByText(text);
          actionResult = success ? 'Clicked "$text"' : 'Could not find "$text" to click';
          break;

        case 'click_at':
          final x = (params['x'] as num?)?.toDouble() ?? 0;
          final y = (params['y'] as num?)?.toDouble() ?? 0;
          // Use Shizuku for exact coordinates for better reliability
          if (_shizukuService.isAvailable && _shizukuService.hasPermission) {
            await _shizukuService.tapXY(x.toInt(), y.toInt());
            success = true;
          } else {
            success = await _screenService.clickAt(x, y);
          }
          actionResult = success ? 'Clicked at ($x, $y)' : 'Click failed';
          break;

        case 'type_text':
          final text = params['text'] as String? ?? '';
          final hint = params['field_hint'] as String?;
          // Inject via Shizuku if available to avoid keyboard issues
          if (_shizukuService.isAvailable && _shizukuService.hasPermission) {
             await _shizukuService.injectText(text);
             success = true;
          } else {
             success = await _screenService.typeText(text, fieldHint: hint);
          }
          actionResult = success ? 'Typed "$text"' : 'Could not type text';
          break;

        case 'scroll':
          final direction = params['direction'] as String? ?? 'down';
          success = await _screenService.scroll(direction);
          actionResult = success ? 'Scrolled $direction' : 'Scroll failed';
          break;

        case 'press_back':
          success = await _screenService.pressBack();
          actionResult = 'Pressed back';
          break;

        case 'press_home':
          success = await _screenService.pressHome();
          actionResult = 'Pressed home';
          break;

        case 'open_app':
          final appName = params['app_name'] as String? ?? '';
          actionResult = await _appLauncher.openApp(appName);
          success = actionResult.startsWith('Opened');
          break;

        case 'wait':
          await Future.delayed(const Duration(seconds: 1));
          actionResult = 'Waited';
          success = true;
          break;
          
        case 'request_vision':
          _report('Requesting Vision Fallback...');
          actionResult = await _executeVisionFallback(userGoal);
          success = actionResult.contains('Vision action executed');
          break;

        case 'done':
          results.add('Task complete: $reasoning');
          _report('Task complete: $reasoning');
          _notificationService.showTaskCompleteNotification('Task Completed', reasoning);
          return results.join('\n');

        default:
          actionResult = 'Unknown action: $action';
      }

      developer.log('=== NATIVE EXECUTION RESULT ===\n$actionResult', name: 'PrivateAgent');

      results.add('Step ${step + 1}: $actionResult ($reasoning)');
      
      // Update scratchpad for sliding window
      _scratchpad.add('Step ${step + 1}: Action=$action, Result=$actionResult');
      if (_scratchpad.length > 5) {
        _scratchpad.removeAt(0);
      }

      if (isComplete) {
        results.add('Task complete.');
        _report('Task complete.');
        _notificationService.showTaskCompleteNotification('Task Completed', 'Agent finished its goal.');
        return results.join('\n');
      }
    }

    results.add('Reached maximum steps (${_aiService.maxSteps}). Task may be incomplete.');
    _report('Reached maximum steps.');
    _notificationService.showTaskCompleteNotification('Task Stopped', 'Reached maximum steps (${_aiService.maxSteps}).');
    return results.join('\n');
  }

  Future<String> _executeVisionFallback(String goal) async {
    final screenshotPayload = await _screenService.takeScreenshot();
    
    if (screenshotPayload == null || screenshotPayload.isEmpty) {
      return 'Vision Fallback failed: Could not capture native screenshot (Requires Android 11+).';
    }
    
    try {
      // The native service appends "scaleFactor|base64" to avoid dart-side image parsing OOMs
      final parts = screenshotPayload.split('|');
      if (parts.length != 2) return 'Vision Fallback failed: Invalid payload format.';
      
      final scaleFactor = double.tryParse(parts[0]) ?? 1.0;
      final base64Image = parts[1];
      
      final visionPrompt = '''TASK: $goal
You are a Vision AI fallback. Look at this Android screenshot. Output ONLY strict JSON:
{"action": "click_xy", "x": 123, "y": 456, "reasoning": "why"}''';

      final response = await _aiService.sendStatelessMessage(
        visionPrompt, 
        systemOverride: 'You are an Android Vision AI.', 
        base64Image: base64Image
      );
      
      String jsonStr = response.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch != null) jsonStr = jsonMatch.group(0)!;
      final actionMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      if (actionMap['action'] == 'click_xy') {
        int x = (actionMap['x'] as num).toInt();
        int y = (actionMap['y'] as num).toInt();
        // Scale the AI's 720p coordinate choice back up to native screen resolution
        final targetX = (x / scaleFactor).toInt();
        final targetY = (y / scaleFactor).toInt();
        
        if (_shizukuService.isAvailable && _shizukuService.hasPermission) {
          await _shizukuService.tapXY(targetX, targetY);
        } else {
          await _screenService.clickAt(targetX.toDouble(), targetY.toDouble());
        }
        return 'Vision action executed: clicked ($targetX, $targetY)';
      }
      return 'Vision fallback skipped action: $response';
    } catch (e) {
      return 'Vision API Error: $e';
    }
  }
}
