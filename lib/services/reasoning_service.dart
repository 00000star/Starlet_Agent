import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
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

    // Prune the UI tree to save data and tokens
    final prunedState = _pruneTree(currentScreenState);
    final minifiedState = jsonEncode(prunedState);

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
    
    final file = File(screenshotPath);
    if (!await file.exists()) {
      throw Exception('Screenshot failed to save at $screenshotPath.');
    }
    
    try {
      final bytes = await file.readAsBytes();
      
      // Downscale to save RAM and tokens
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Failed to decode screenshot image.');
      final resized = img.copyResize(decoded, width: 720); // 720p width
      final compressed = img.encodeJpg(resized, quality: 60);
      final base64Image = base64Encode(compressed);
  
      // Note: As of late 2024, DeepSeek API does not natively support deepseek-vl image payloads on the chat endpoint.
      // If this fails, the user must point to an OpenAI-compatible vision endpoint in the backend.
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat', 
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'You are a Vision AI fallback. Look at this Android screenshot. Output ONLY strict JSON: {"action": "click_xy", "x": 123, "y": 456}'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image'
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
          // Map back to original resolution if needed, but tapXY uses absolute pixels.
          // Wait, if we resized the image sent to AI, the AI will output coordinates for the 720p image!
          // We must scale the tap back up to the actual device resolution.
          final scaleFactor = decoded.width / 720;
          await _shizukuService.tapXY((x * scaleFactor).toInt(), (y * scaleFactor).toInt());
        } else {
          throw Exception('Vision fallback returned invalid action: $content');
        }
      } else {
        throw Exception('Vision API failed: \${response.statusCode} - \${response.body}');
      }
    } finally {
      // Cleanup screenshot to prevent storage leak
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  List<int>? _findNodeCenter(Map<String, dynamic> node, String targetId) {
    if (node['id']?.toString() == targetId) {
      if (node['bounds'] != null && node['bounds'] is List && (node['bounds'] as List).length >= 4) {
        final bounds = node['bounds'] as List<dynamic>;
        int x = (bounds[0] + bounds[2]) ~/ 2;
        int y = (bounds[1] + bounds[3]) ~/ 2;
        return [x, y];
      } else {
        throw Exception("Node ID $targetId found but has no valid bounds (possibly invisible/off-screen)");
      }
    }
    if (node['children'] != null && node['children'] is List) {
      for (var child in node['children']) {
        if (child is Map<String, dynamic>) {
          final result = _findNodeCenter(child, targetId);
          if (result != null) return result;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _pruneTree(Map<String, dynamic> node) {
    final pruned = <String, dynamic>{};
    if (node.containsKey('id')) pruned['id'] = node['id'];
    if (node.containsKey('text') && node['text'] != null && node['text'].toString().isNotEmpty) pruned['text'] = node['text'];
    if (node.containsKey('contentDescription') && node['contentDescription'] != null) pruned['desc'] = node['contentDescription'];
    if (node.containsKey('bounds')) pruned['bounds'] = node['bounds'];
    
    if (node.containsKey('children') && node['children'] is List) {
      final children = <Map<String, dynamic>>[];
      for (var child in node['children']) {
        if (child is Map<String, dynamic>) {
          // Skip if invisible
          if (child['isVisible'] == false) continue;
          final prunedChild = _pruneTree(child);
          if (prunedChild.isNotEmpty) {
            children.add(prunedChild);
          }
        }
      }
      if (children.isNotEmpty) pruned['children'] = children;
    }
    return pruned;
  }
}
