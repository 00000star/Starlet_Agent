import 'dart:ui';
import '../services/task_executor.dart';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/voice_service.dart';
import '../widgets/message_bubble.dart';
import '../services/telegram_service.dart';
import '../widgets/emergency_halt_button.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final ActionHandler _actionHandler = ActionHandler();
  final VoiceService _voiceService = VoiceService();
  late final TelegramService _telegramService;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _telegramService = TelegramService(_actionHandler, _aiService);
    _initServices();
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _voiceService.init();
    await _telegramService.init();

    // Check Shizuku availability
    await _actionHandler.shizuku.checkAvailability();

    if (mounted) {
      // Check accessibility service
      final accessibilityEnabled =
          await _actionHandler.screenAutomation.isServiceRunning();

      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content:
              'Hi! I\'m Starlet. I can help you control your phone.\n\n'
              '${accessibilityEnabled ? '✅ Screen Control is ACTIVE — I can read and control other apps!' : '⚠️ Screen Control is OFF — Go to Settings to enable it for multi-step tasks.'}\n\n'
              'Try saying:\n'
              '• "Open YouTube"\n'
              '• "Call Mom"\n'
              '• "Set volume to 50%"\n'
              '• "What\'s on my screen?"\n\n'
              'Type or tap the mic to get started!',
        ));
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      // Get AI response
      final response = await _aiService.sendMessage(text.trim());

      // Check if it's an action
      final action = _aiService.parseAction(response);

      if (action != null) {
        // Execute the action (pass aiService for multi-step tasks)
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            if (mounted) {
              setState(() {
                _messages.add(ChatMessage(role: 'assistant', content: '⏳ $msg'));
              });
              _scrollToBottom();
            }
          },
        );

        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: action.response.isNotEmpty
                ? action.response
                : result.details ?? 'Done.',
            actionResult: result,
          ));
        });

        // Speak the response
        _voiceService.speak(action.response.isNotEmpty
            ? action.response
            : result.details ?? 'Done.');
      } else {
        // Plain text response
        setState(() {
          _messages.add(ChatMessage(role: 'assistant', content: response));
        });
        _voiceService.speak(response);
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        ));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);

    await _voiceService.startListening(
      onResult: (text) {
        _sendMessage(text);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _telegramService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starlet'),
        actions: [
          // Screen control test button
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: 'Test screen reading',
            onPressed: () async {
              final isRunning = await _actionHandler.screenAutomation
                  .isServiceRunning();
              if (!isRunning) {
                setState(() {
                  _messages.add(ChatMessage(
                    role: 'assistant',
                    content:
                        '❌ Screen Control is not enabled!\n\n'
                        'To enable it:\n'
                        '1. Go to Settings (⚙️ icon)\n'
                        '2. Find "Screen Control (Accessibility)"\n'
                        '3. Tap "Open Accessibility Settings"\n'
                        '4. Find "Starlet Screen Control"\n'
                        '5. Toggle it ON',
                  ));
                });
                _scrollToBottom();
                return;
              }
              setState(() {
                _messages.add(ChatMessage(
                  role: 'assistant',
                  content: '🔍 Reading screen...',
                ));
              });
              _scrollToBottom();
              final description = await _actionHandler.screenAutomation
                  .getScreenDescription();
              setState(() {
                _messages.add(ChatMessage(
                  role: 'assistant',
                  content: '📱 Screen Content:\n\n$description',
                ));
              });
              _scrollToBottom();
            },
          ),
          // Shizuku status indicator
          if (_actionHandler.shizuku.isAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.link,
                size: 18,
                color: _actionHandler.shizuku.hasPermission
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _aiService.clearHistory();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    aiService: _aiService,
                    shizukuService: _actionHandler.shizuku,
                    screenAutomationService: _actionHandler.screenAutomation,
                    telegramService: _telegramService,
                  ),
                ),
              );
              // Refresh Shizuku status after settings
              await _actionHandler.shizuku.checkAvailability();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0F),
              Color(0xFF18152E),
              Color(0xFF0A0A0F),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          children: [
          // API key warning
          if (!_aiService.isConfigured)
            MaterialBanner(
              content: const Text(
                'API key not set. Go to Settings to add your DeepSeek API key.',
              ),
              leading: const Icon(Icons.warning, color: Colors.orange),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          aiService: _aiService,
                          shizukuService: _actionHandler.shizuku,
                          screenAutomationService: _actionHandler.screenAutomation,
                          telegramService: _telegramService,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  child: const Text('SETTINGS'),
                ),
              ],
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

          // Input bar
          ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                      width: 1.0,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      // Glowing Mic button
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: _isListening ? [
                            BoxShadow(
                              color: const Color(0xFFFF3366).withOpacity(0.6),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ] : [],
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            color: _isListening
                                ? const Color(0xFFFF3366)
                                : const Color(0xFF00FFC6),
                          ),
                          onPressed: _isLoading ? null : _toggleVoice,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Text input
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _isListening
                                ? 'Listening...'
                                : 'Type a command...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: Color(0xFF6C63FF),
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.3),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted:
                              _isLoading ? null : (text) => _sendMessage(text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send / Halt button
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isLoading 
                              ? const Color(0xFFFF3366).withOpacity(0.15) 
                              : const Color(0xFF6C63FF).withOpacity(0.15),
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isLoading ? Icons.stop_rounded : Icons.send_rounded,
                          ),
                          color: _isLoading
                              ? const Color(0xFFFF3366)
                              : const Color(0xFF6C63FF),
                          onPressed: _isLoading
                              ? () {
                                  // Trigger Emergency Halt
                                  TaskExecutor.isHalted = true;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Emergency Halt Triggered! Stopping loop...')),
                                  );
                                }
                              : () => _sendMessage(_textController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}
