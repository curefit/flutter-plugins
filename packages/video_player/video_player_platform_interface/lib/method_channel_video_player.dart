// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'messages.dart';
import 'video_player_platform_interface.dart';

/// An implementation of [VideoPlayerPlatform] that uses method channels.
class MethodChannelVideoPlayer extends VideoPlayerPlatform {
  VideoPlayerApi _api = VideoPlayerApi();

  @override
  Future<void> init(int maxCacheSize, int maxCacheFileSize) {
    InitializeMessage message = InitializeMessage();
    message.maxCacheSize = maxCacheSize;
    message.maxCacheFileSize = maxCacheFileSize;
    return _api.initialize(message);
  }

  @override
  Future<void> dispose(int textureId) {
    return _api.dispose(TextureMessage()..textureId = textureId);
  }

  @override
  Future<int?> create() async {
    CreateMessage message = CreateMessage();
    message.useCache = true;
    TextureMessage response = await _api.create(message);
    return response.textureId;
  }

  @override
  Future<void> setDataSource(int textureId, DataSource dataSource) async {
    DataSourceMessage dataSourceMessage = DataSourceMessage();
    dataSourceMessage.key = dataSource.key;
    dataSourceMessage.textureId = textureId;
    dataSourceMessage.useCache = true;
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        dataSourceMessage.uri = dataSource.asset;
        dataSourceMessage.asset = dataSource.asset;
        dataSourceMessage.packageName = dataSource.package;
        break;
      case DataSourceType.network:
        dataSourceMessage.uri = dataSource.uri;
        dataSourceMessage.formatHint = dataSource.rawFormalHint;
        break;
      case DataSourceType.file:
        dataSourceMessage.uri = dataSource.uri;
        break;
    }

    await _api.setDataSource(dataSourceMessage);
  }

  @override
  Future<void> setLooping(int textureId, bool looping) {
    return _api.setLooping(LoopingMessage()
      ..textureId = textureId
      ..isLooping = looping);
  }

  @override
  Future<void> play(int textureId) {
    return _api.play(TextureMessage()..textureId = textureId);
  }

  @override
  Future<void> pause(int textureId) {
    return _api.pause(TextureMessage()..textureId = textureId);
  }

  @override
  Future<void> setVolume(int textureId, double volume) {
    return _api.setVolume(VolumeMessage()
      ..textureId = textureId
      ..volume = volume);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) {
    assert(speed > 0);

    return _api.setPlaybackSpeed(PlaybackSpeedMessage()
      ..textureId = textureId
      ..speed = speed);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return _api.seekTo(PositionMessage()
      ..textureId = textureId
      ..position = position.inMilliseconds);
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    PositionMessage response =
        await _api.position(TextureMessage()..textureId = textureId);
    return Duration(milliseconds: response.position!);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _eventChannelFor(textureId)
        .receiveBroadcastStream()
        .map((dynamic event) {
      final Map<dynamic, dynamic> map = event;
      switch (map['event']) {
        case 'initialized':
          return VideoEvent(
            key: map['key'],
            eventType: VideoEventType.initialized,
            duration: Duration(milliseconds: map['duration']),
            size: Size(map['width']?.toDouble() ?? 0.0,
                map['height']?.toDouble() ?? 0.0),
          );
        case 'completed':
          return VideoEvent(
            key: map['key'],
            eventType: VideoEventType.completed,
          );
        case 'bufferingUpdate':
          final List<dynamic> values = map['values'];

          return VideoEvent(
            key: map['key'],
            buffered: values.map<DurationRange>(_toDurationRange).toList(),
            eventType: VideoEventType.bufferingUpdate,
          );
        case 'bufferingStart':
          return VideoEvent(
            eventType: VideoEventType.bufferingStart,
            key: map['key'],
          );
        case 'bufferingEnd':
          return VideoEvent(
            eventType: VideoEventType.bufferingEnd,
            key: map['key'],
          );
        default:
          return VideoEvent(
            eventType: VideoEventType.unknown,
            key: map['key'],
          );
      }
    });
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) {
    return _api.setMixWithOthers(
      MixWithOthersMessage()..mixWithOthers = mixWithOthers,
    );
  }

  EventChannel _eventChannelFor(int textureId) {
    return EventChannel('flutter.io/videoPlayer/videoEvents$textureId');
  }

  static const Map<VideoFormat, String> _videoFormatStringMap =
      <VideoFormat, String>{
    VideoFormat.ss: 'ss',
    VideoFormat.hls: 'hls',
    VideoFormat.dash: 'dash',
    VideoFormat.other: 'other',
  };

  DurationRange _toDurationRange(dynamic value) {
    final List<dynamic> pair = value;
    return DurationRange(
      Duration(milliseconds: pair[0]),
      Duration(milliseconds: pair[1]),
    );
  }
}
