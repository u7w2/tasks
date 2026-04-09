import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _askConfirmation = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // setting is "hide prompt", so "ask confirmation" is the inverse
        _askConfirmation = !(prefs.getBool('hide_delete_workflow_prompt') ?? false);
      });
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Ask confirmation to delete workflow'),
            subtitle: const Text('Show a confirmation dialog before deleting an entire workflow'),
            value: _askConfirmation,
            onChanged: _toggleConfirmation,
          ),
        ],
      ),
    );
  }
}
