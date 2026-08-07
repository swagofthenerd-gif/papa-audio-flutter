import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'theme.dart';
import '../models.dart';

/// YouTube comments browser for a video.
class YoutubeCommentsPage extends StatefulWidget {
  final String videoId;
  final String videoTitle;
  const YoutubeCommentsPage({super.key, required this.videoId, required this.videoTitle});
  @override
  State<YoutubeCommentsPage> createState() => _YoutubeCommentsPageState();
}

class _YoutubeCommentsPageState extends State<YoutubeCommentsPage> {
  List<YtComment> _comments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(
        Uri.parse('https://www.youtube.com/youtubei/v1/next?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8'),
        headers: {'Content-Type': 'application/json'},
        // NOTE: InnerTube context is needed for real API; this is a simplified example
      );
      // Simplified — real implementation would parse InnerTube response
      if (res.statusCode == 200) {
        // Try to extract comments from the response
        // For now, show demo content
        setState(() { _loading = false; _comments = _parseComments(res.body); });
      } else {
        setState(() { _loading = false; _error = 'Failed to load comments'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Network error: $e'; });
    }
  }

  List<YtComment> _parseComments(String body) {
    // Simplified parser — real implementation would use the InnerTube response structure
    try {
      final json = jsonDecode(body);
      final comments = <YtComment>[];
      // Walk continuation items... (simplified)
      return comments;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.videoTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Comments')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off, size: 48, color: PapaColors.textMuted),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: PapaColors.textSecondary)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
            ]))
          : _comments.isEmpty
            ? const Center(child: Text('No comments yet', style: TextStyle(color: PapaColors.textMuted)))
            : ListView.builder(
                itemCount: _comments.length,
                itemBuilder: (ctx, i) => _commentCard(_comments[i]),
              ),
    );
  }

  Widget _commentCard(YtComment c) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    color: PapaColors.card,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 16, backgroundImage: c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
            child: c.avatarUrl == null ? const Icon(Icons.person, size: 16) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.author, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(c.timeAgo, style: const TextStyle(color: PapaColors.textMuted, fontSize: 11)),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.thumb_up_alt_outlined, size: 16, color: PapaColors.textMuted),
            const SizedBox(width: 4),
            Text('${c.likes}', style: const TextStyle(color: PapaColors.textMuted, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(c.text, style: const TextStyle(fontSize: 14)),
        if (c.replies > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${c.replies} replies', style: const TextStyle(color: PapaColors.accent, fontSize: 12)),
          ),
      ]),
    ),
  );
}

class YtComment {
  final String author;
  final String? avatarUrl;
  final String text;
  final String timeAgo;
  final int likes;
  final int replies;
  const YtComment({required this.author, this.avatarUrl, required this.text,
    required this.timeAgo, this.likes = 0, this.replies = 0});
}
