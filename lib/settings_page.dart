import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_generator_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _askConfirmation = true;
  final TextEditingController _apiKeyController = TextEditingController();
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _askConfirmation = !(prefs.getBool('hide_delete_workflow_prompt') ?? false);
        _apiKeyController.text = prefs.getString('ai_api_key') ?? '';
      });
    }
  }

  Future<void> _saveApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_api_key', value);
  }

  Future<void> _toggleConfirmation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_delete_workflow_prompt', !value);
    if (mounted) {
      setState(() {
        _askConfirmation = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask confirmation to delete workflow',
                          style: TextStyle(fontSize: 16)),
                      SizedBox(height: 4),
                      Text(
                          'Show a confirmation dialog before deleting an entire workflow',
                          style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                ),
                PlatformSwitch(
                  value: _askConfirmation,
                  onChanged: _toggleConfirmation,
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Project Generator',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Enter your API Key to enable real-time project generation. Supports Gemini / OpenAI compatible endpoints.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                PlatformTextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  onChanged: _saveApiKey,
                  material: (_, __) => MaterialTextFieldData(
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  cupertino: (_, __) => CupertinoTextFieldData(
                    placeholder: 'Enter API Key',
                    suffix: PlatformIconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(_obscureKey
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: PlatformElevatedButton(
                    onPressed: () async {
                      final result = await AIGeneratorService.testConnection();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result ?? "Unknown error"),
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    },
                    child: const Text('Test AI Connection'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
