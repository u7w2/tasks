import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'graph_provider.dart';

class MagicTemplate {
  final String name;
  final List<String> nodeNames;
  final List<List<int>> links; // Index pairs [parentIndex, childIndex]

  MagicTemplate({
    required this.name,
    required this.nodeNames,
    required this.links,
  });

  Map<String, dynamic> toJson() => {'nodes': nodeNames, 'links': links};

  factory MagicTemplate.fromJson(String name, Map<String, dynamic> json) {
    // Try to find nodes under various synonyms
    final dynamic rawNodes =
        json['nodes'] ?? json['tasks'] ?? json['steps'] ?? json['elements'];
    if (rawNodes == null)
      throw Exception("Could not find nodes/tasks in AI response");

    // Try to find links under various synonyms
    final dynamic rawLinks =
        json['links'] ??
        json['dependencies'] ??
        json['edges'] ??
        json['relationships'];
    if (rawLinks == null)
      throw Exception("Could not find links/dependencies in AI response");

    return MagicTemplate(
      name: name,
      nodeNames: List<String>.from(rawNodes),
      links: (rawLinks as List).map((l) => List<int>.from(l)).toList(),
    );
  }
}

class AIGeneratorService {
  static const String _geminiBaseUrl = "generativelanguage.googleapis.com";
  static const String _geminiPath = "v1/models/gemini-1.5-flash:generateContent";

  static final List<MagicTemplate> templates = [
    // ... templates stay the same ...
    MagicTemplate(
      name: "Standard Project Plan",
      nodeNames: [
        "Project Goal",
        "Phase 1: Research",
        "Phase 2: Design",
        "Phase 3: Implementation",
        "Phase 4: Launch",
        "Post-Launch Review",
      ],
      links: [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [4, 5],
      ],
    ),
    MagicTemplate(
      name: "Product Launch",
      nodeNames: [
        "Launch Product",
        "Market Strategy",
        "Social Media Teasers",
        "Influencer Outreach",
        "Email Campaign",
        "Analytics Setup",
      ],
      links: [
        [0, 1],
        [0, 2],
        [0, 3],
        [0, 4],
        [0, 5],
      ],
    ),
    MagicTemplate(
      name: "Event Planning",
      nodeNames: [
        "Successful Event",
        "Venue Selection",
        "Budget Approval",
        "Guest List & Invitations",
        "Catering & Logistics",
        "Day-of Coordination",
      ],
      links: [
        [0, 1],
        [1, 2],
        [0, 3],
        [0, 4],
        [4, 5],
      ],
    ),
    MagicTemplate(
      name: "Software Development",
      nodeNames: [
        "Feature Release",
        "Requirements Doc",
        "System Architecture",
        "Core Implementation",
        "Bug Fixing",
        "Beta Group Testing",
      ],
      links: [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [4, 5],
      ],
    ),
  ];

  static Future<String?> testConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('ai_api_key');
    if (apiKey == null || apiKey.isEmpty) return "No API Key found in settings";

    try {
      final uri = Uri.https(_geminiBaseUrl, "v1beta/models", {'key': apiKey});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List models = data['models'] ?? [];
        final supported = models
            .where((m) => (m['supportedGenerationMethods'] as List)
                .contains('generateContent'))
            .map((m) => (m['name'] as String).replaceFirst('models/', ''))
            .toList();

        if (supported.isNotEmpty) {
          await prefs.setString('ai_discovered_model', supported.first);
          return "Success! Found ${supported.length} models. Using ${supported.first}.";
        }
        return "Connected, but no compatible generation models found.";
      }
      return "Connection failed: ${response.statusCode} - ${response.body}";
    } catch (e) {
      return "Network error: $e";
    }
  }

  static Future<MagicTemplate> generate(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('ai_api_key');

    if (apiKey == null || apiKey.isEmpty) {
      return _generateLocal(prompt);
    }

    final String? discovered = prefs.getString('ai_discovered_model');
    final List<String> modelIds = [
      if (discovered != null) discovered,
      "gemini-1.5-flash",
      "gemini-1.5-flash-latest",
      "gemini-pro",
    ];

    Object? lastError;

    for (final modelId in modelIds) {
      try {
        final path = "v1beta/models/$modelId:generateContent";
        final uri = Uri.https(_geminiBaseUrl, path, {'key': apiKey});

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "contents": [
              {
                "role": "user",
                "parts": [
                  {
                    "text":
                        "Plan this: '$prompt'. Return ONLY a JSON object: { \"nodes\": [\"Task Names\"], \"links\": [[parentIdx, childIdx]] }."
                  }
                ]
              }
            ],
            "generationConfig": {
              "temperature": 0.7,
              "maxOutputTokens": 2048,
            },
          }),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String text = data['candidates'][0]['content']['parts'][0]['text'];

          text = text.trim();
          if (text.startsWith('```')) {
            final lines = text.split('\n');
            if (lines.length > 2) {
              text = lines.sublist(1, lines.length - 1).join('\n');
            }
          }

          final cleanJson = jsonDecode(text.trim());
          return MagicTemplate.fromJson(prompt, cleanJson);
        } else {
          lastError = "Model $modelId: ${response.statusCode}";
          if (discovered == modelId) {
             debugPrint("Discovered model failed, trying fallbacks...");
          }
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(lastError ?? "Auto-discovery failed. Check your API key.");
  }

  static MagicTemplate _generateLocal(String prompt) {
    String p = prompt.toLowerCase();
    if (p.contains("product") || p.contains("launch") || p.contains("market")) {
      return templates[1];
    }
    if (p.contains("event") || p.contains("party") || p.contains("meeting")) {
      return templates[2];
    }
    if (p.contains("code") ||
        p.contains("dev") ||
        p.contains("app") ||
        p.contains("software")) {
      return templates[3];
    }
    return templates[0];
  }

  static void executeGeneration(
    GraphProvider graph,
    MagicTemplate template, {
    CategoryNode? anchor,
  }) {
    graph.executeBatch(() {
      Map<int, CategoryNode> createdNodes = {};

      // Create all nodes first (silently to avoid individual snapshots)
      for (int i = 0; i < template.nodeNames.length; i++) {
        var node = graph.addNode(template.nodeNames[i], silent: true);
        createdNodes[i] = node;
      }

      // Anchor first node to parent if provided
      if (anchor != null && createdNodes.containsKey(0)) {
        graph.addLink(anchor, createdNodes[0]!, silent: true);
      }

      // Create links silently
      for (var link in template.links) {
        var parent = createdNodes[link[0]];
        var child = createdNodes[link[1]];
        if (parent != null && child != null) {
          graph.addLink(parent, child, silent: true);
        }
      }
    });
  }
}
