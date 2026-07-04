import 'dart:convert';
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
        await _executeAction(actionMap);
        
        // Update scratchpad for context window management
        _scratchpad.add(content);
      } catch (e) {
        print('Error parsing or executing JSON: $e');
        _scratchpad.add('Error executing last action: $content');
      }
    } else {
      throw Exception('Failed to communicate with DeepSeek API: ${response.statusCode}');
    }
  }

  Future<void> _executeAction(Map<String, dynamic> actionMap) async {
    final action = actionMap['action'];
    
    switch (action) {
      case 'click':
        final id = actionMap['id'];
        await _shizukuService.tapElement(id); // Assumes ShizukuService has tap capability
        break;
      case 'text_inject':
        final id = actionMap['id'];
        final text = actionMap['text'];
        await _shizukuService.injectText(id, text); // Assumes ShizukuService has text injection
        break;
      case 'request_vision':
        print('Vision requested - to be implemented');
        break;
      case 'done':
        print('Goal achieved!');
        _scratchpad.clear(); // Clear scratchpad for the next objective
        break;
      default:
        print('Unknown action: $action');
    }
  }
}
