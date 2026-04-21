import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import '../graph_provider.dart';
import '../ai_generator_service.dart';

class MagicDialog extends StatefulWidget {
  final GraphProvider graph;
  const MagicDialog({super.key, required this.graph});

  @override
  MagicDialogState createState() => MagicDialogState();
}

class MagicDialogState extends State<MagicDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isGenerating = false;

  void _handleGenerate() async {
    if (_controller.text.trim().isEmpty) return;
    
    setState(() => _isGenerating = true);
    
    try {
      final template = await AIGeneratorService.generate(_controller.text);
      AIGeneratorService.executeGeneration(widget.graph, template);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Magic failed: ${e.toString().replaceAll("Exception: ", "")}"),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
                label: "OK", onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar()),
          ),
        );
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformAlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
          const SizedBox(width: 8),
          const Text("Magic Generator"),
        ],
      ),
      content: _isGenerating 
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.purpleAccent),
              const SizedBox(height: 16),
              const Text("Building your workflow...", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Describe what you want to build and I'll generate the task structure for you."),
              const SizedBox(height: 20),
              PlatformTextField(
                controller: _controller,
                hintText: "Plan a marketing campaign...",
                autofocus: true,
                onSubmitted: (_) => _handleGenerate(),
              ),
            ],
          ),
      actions: [
        if (!_isGenerating)
          PlatformDialogAction(
            child: PlatformText("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
        if (!_isGenerating)
          PlatformDialogAction(
            child: PlatformText("Generate", style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
            onPressed: _handleGenerate,
          ),
      ],
    );
  }
}
