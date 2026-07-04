import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'shizuku_service.dart';

class ReasoningService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ShizukuService _shizukuService;
  
  // State Summarization Scratchpad to remember past steps
  final List<String> _scratchpad = [];
  
  ReasoningService(this._shizukuService);

  Future<void> orchestrate(String goal, Map<String, dynamic> currentScreenState) async {
    final apiKey = await _secureStorage.read(key: 'deepseek_api_key');
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('DeepSeek API key not found in secure storage.');
    }

    // Minify JSON of the Android screen state
    final minifiedState = jsonEncode(currentScreenState);

    // Prepare system prompt with strict JSON schema instructions
    final systemPrompt = '''
You are an Android UI automation agent orchestrating the "Starlet" project.
Your goal is: $goal

You will receive the minified JSON of the current Android screen state.
You must analyze the state and decide the next action.
You have a scratchpad of past actions to avoid repeating mistakes or looping.
If the screen state is identical to the previous step, you must rely on Pure AI Inference to realize you are stuck and try a different approach.

You MUST respond with STRICT JSON adhering to this schema:
{"action": "click", "id": 123} - to click an element by its ID
{"action": "text_inject", "id": 123, "text": "hello"} - to inject text into an element
{"action": "request_vision"} - if you cannot determine what to do and need a screenshot
{"action": "done"} - if the goal is achieved

Do not output any markdown formatting or extra text. Output ONLY valid JSON.
''';

    final prompt = '''
Past Scratchpad Actions:
${_scratchpad.join('\n')}

Current Screen State:
$minifiedState
''';

    final response = await http.post(
      Uri.parse('https://api.deepseek.com/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      final content = responseBody['choices'][0]['message']['content'];
      
      try {
        final actionMap = jsonDecode(content) as Map<String, dynamic>;
        await _executeAction(actionMap, currentScreenState, apiKey);
        
        // Update scratchpad for context window management
        _scratchpad.add(content);
        // Truncate to save RAM (4GB limit) and context window
        if (_scratchpad.length > 5) {
          _scratchpad.removeAt(0);
        }
      } catch (e) {
        print('Error parsing or executing JSON: $e');
        _scratchpad.add('Error executing last action: $e');
      }
    } else {
      throw Exception('Failed to communicate with DeepSeek API: ${response.statusCode}');
    }
  }

  Future<void> _executeAction(Map<String, dynamic> actionMap, Map<String, dynamic> screenState, String apiKey) async {
    final action = actionMap['action'];
    
    switch (action) {
      case 'click':
        final id = actionMap['id'];
        final center = _findNodeCenter(screenState, id.toString());
        if (center != null) {
          await _shizukuService.tapXY(center[0], center[1]);
        } else {
          throw Exception("Node ID $id not found in screen state");
        }
        break;
      case 'text_inject':
        final id = actionMap['id'];
        final text = actionMap['text'];
        final center = _findNodeCenter(screenState, id.toString());
        if (center != null) {
          await _shizukuService.tapXY(center[0], center[1]);
          await Future.delayed(const Duration(milliseconds: 500)); // wait for keyboard
          await _shizukuService.injectText(text);
        } else {
          throw Exception("Node ID $id not found for text injection");
        }
        break;
      case 'request_vision':
        print('Vision requested - executing Vision Fallback');
        await _executeVisionFallback(apiKey);
        break;
      case 'done':
        print('Goal achieved!');
        _scratchpad.clear(); // Clear scratchpad for the next objective
        break;
      default:
        throw Exception('Unknown action: $action');
    }
  }

  Future<void> _executeVisionFallback(String apiKey) async {
    // Take screenshot via Shizuku
    final screenshotPath = '/sdcard/Download/starlet_vision_fallback.png';
    await _shizukuService.takeScreenshot(screenshotPath);
    
    // Read the file and convert to base64
    final file = File(screenshotPath);
    if (!await file.exists()) {
      throw Exception('Screenshot failed.');
    }
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);

    // Call DeepSeek Vision (Assuming deepseek-vl or standard GPT-4-vision-preview compatible API)
    final response = await http.post(
      Uri.parse('https://api.deepseek.com/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat', // or 'deepseek-vl' depending on exact endpoint availability
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'You are a Vision AI fallback. Look at this Android screenshot. Output ONLY strict JSON: {"action": "click_xy", "x": 123, "y": 456}'},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,$base64Image'
                }
              }
            ]
          }
        ],
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      final content = responseBody['choices'][0]['message']['content'];
      final actionMap = jsonDecode(content) as Map<String, dynamic>;
      
      if (actionMap['action'] == 'click_xy') {
        int x = actionMap['x'];
        int y = actionMap['y'];
        await _shizukuService.tapXY(x, y);
      } else {
        throw Exception('Vision fallback returned invalid action.');
      }
    } else {
      throw Exception('Vision API failed: ${response.statusCode}');
    }
    
    // Cleanup screenshot
    await file.delete();
  }

  List<int>? _findNodeCenter(Map<String, dynamic> node, String targetId) {
    if (node['id']?.toString() == targetId) {
      if (node['bounds'] != null) {
        // bounds: [left, top, right, bottom]
        final bounds = node['bounds'] as List<dynamic>;
        int x = (bounds[0] + bounds[2]) ~/ 2;
        int y = (bounds[1] + bounds[3]) ~/ 2;
        return [x, y];
      }
    }
    if (node['children'] != null) {
      for (var child in node['children']) {
        final result = _findNodeCenter(child as Map<String, dynamic>, targetId);
        if (result != null) return result;
      }
    }
    return null;
  }
}
