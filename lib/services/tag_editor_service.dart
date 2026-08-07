import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_taglib/flutter_taglib.dart';

/// Holds all tag fields for a single audio file.
class TagData {
  String? title;
  String? artist;
  String? album;
  String? albumArtist;
  String? genre;
  int? year;
  int? trackNumber;
  int? trackTotal;
  int? discNumber;
  int? discTotal;
  String? comment;
  Uint8List? artwork;

  TagData({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.discTotal,
    this.comment,
    this.artwork,
  });

  bool get hasArtwork => artwork != null && artwork!.isNotEmpty;
}

/// Service for reading and writing audio file metadata via flutter_taglib.
class TagEditorService {
  /// Reads all metadata tags from [filePath].
  /// Returns a [TagData] with the parsed fields, or throws on failure.
  Future<TagData> readTags(String filePath) async {
    final file = await TagLibFile.openAsync(filePath);
    if (file == null) {
      throw Exception(
          'Could not open file for reading tags: $filePath\n${TagLibFile.lastError ?? "Unknown error"}');
    }
    try {
      final data = TagData();
      data.title = file.title;
      data.artist = file.artist;
      data.album = file.album;
      data.genre = file.genre;
      data.comment = file.comment;
      data.year = file.year;
      data.trackNumber = file.track;

      // Read extended properties (album artist, disc number, etc.)
      final props = file.properties;
      data.albumArtist = _first(props, 'ALBUMARTIST');
      data.discNumber = _intOrNull(_first(props, 'DISCNUMBER'));
      data.discTotal = _intOrNull(_first(props, 'DISCTOTAL'));
      data.trackTotal = _intOrNull(_first(props, 'TRACKTOTAL'));

      // Artwork
      data.artwork = file.coverData;

      return data;
    } finally {
      file.close();
    }
  }

  /// Writes [data] tags to the file at [filePath].
  Future<void> writeTags(String filePath, TagData data) async {
    final file = await TagLibFile.openAsync(filePath, writeAccess: true);
    if (file == null) {
      throw Exception(
          'Could not open file for writing tags: $filePath\n${TagLibFile.lastError ?? "Unknown error"}');
    }
    try {
      if (data.title != null) file.title = data.title!;
      if (data.artist != null) file.artist = data.artist!;
      if (data.album != null) file.album = data.album!;
      if (data.genre != null) file.genre = data.genre!;
      if (data.comment != null) file.comment = data.comment!;
      if (data.year != null) file.year = data.year!;
      if (data.trackNumber != null) file.track = data.trackNumber!;

      // Extended properties
      final extProps = <String, List<String>>{};
      if (data.albumArtist != null) {
        extProps['ALBUMARTIST'] = [data.albumArtist!];
      }
      if (data.discNumber != null) {
        extProps['DISCNUMBER'] = ['${data.discNumber}'];
      }
      if (data.discTotal != null) {
        extProps['DISCTOTAL'] = ['${data.discTotal}'];
      }
      if (data.trackTotal != null) {
        extProps['TRACKTOTAL'] = ['${data.trackTotal}'];
      }
      if (extProps.isNotEmpty) {
        file.setProperties(extProps);
      }

      if (!file.save()) {
        throw Exception(
            'Failed to save tags: ${TagLibFile.lastError ?? "Unknown error"}');
      }
    } finally {
      file.close();
    }
  }

  /// Writes only the artwork to [filePath].
  Future<void> writeArtwork(String filePath, Uint8List imageBytes) async {
    final mime = _detectMime(imageBytes);
    final file = await TagLibFile.openAsync(filePath, writeAccess: true);
    if (file == null) {
      throw Exception(
          'Could not open file for writing artwork: $filePath\n${TagLibFile.lastError ?? "Unknown error"}');
    }
    try {
      file.setCover(data: imageBytes, mimeType: mime);
      if (!file.save()) {
        throw Exception(
            'Failed to save artwork: ${TagLibFile.lastError ?? "Unknown error"}');
      }
    } finally {
      file.close();
    }
  }

  /// Detect mime type from magic bytes (simple but good enough for JPEG/PNG).
  static String _detectMime(Uint8List bytes) {
    if (bytes.length < 4) return 'image/jpeg';
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    // BMP: BM
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return 'image/jpeg';
  }

  static String? _first(Map<String, List<String>> props, String key) {
    final vals = props[key];
    if (vals == null || vals.isEmpty) return null;
    return vals.first;
  }

  static int? _intOrNull(String? s) {
    if (s == null) return null;
    final parts = s.split('/');
    return int.tryParse(parts.first.trim());
  }
}
