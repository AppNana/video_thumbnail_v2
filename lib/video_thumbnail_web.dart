import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:get_thumbnail_video/src/image_format.dart';
import 'package:get_thumbnail_video/src/video_thumbnail_platform.dart';
import 'package:web/web.dart';

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage = 'No further diagnostic information can be determined or provided.';

/// A web implementation of the VideoThumbnailPlatform of the VideoThumbnail plugin.
class VideoThumbnailWeb extends VideoThumbnailPlatform {
  /// Constructs a VideoThumbnailWeb
  VideoThumbnailWeb();

  static void registerWith(Registrar registrar) {
    VideoThumbnailPlatform.instance = VideoThumbnailWeb();
  }

  @override
  Future<XFile> thumbnailFile({
    required String video,
    required Map<String, String>? headers,
    required String? thumbnailPath,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );

    return XFile(URL.createObjectURL(blob), mimeType: blob.type);
  }

  @override
  Future<Uint8List> thumbnailData({
    required String video,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );
    final path = URL.createObjectURL(blob);
    final file = XFile(path, mimeType: blob.type);
    final bytes = await file.readAsBytes();
    URL.revokeObjectURL(path);

    return bytes;
  }

  Future<Blob> _createThumbnail({
    required String videoSrc,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final completer = Completer<Blob>();

    final timeSec = math.max(timeMs / 1000, 0);

    final video = HTMLVideoElement()
      ..src = videoSrc
      ..autoplay = true
      ..playsInline = true
      ..muted = true;

    document.body!.append(video);

    video.onLoadedMetadata.listen((event) {
      video.currentTime = timeSec;
    });

    video.onSeeked.listen((Event e) async {
      await Future.delayed(Duration(seconds: 1));
      if (!completer.isCompleted) {
        final canvas = HTMLCanvasElement();
        final ctx = canvas.context2D;

        if (maxWidth == 0 && maxHeight == 0) {
          canvas
            ..width = video.videoWidth
            ..height = video.videoHeight;
          ctx.drawImage(video, 0, 0);
        } else {
          final aspectRatio = video.videoWidth / video.videoHeight;
          if (maxWidth == 0) {
            maxWidth = (maxHeight * aspectRatio).round();
          } else if (maxHeight == 0) {
            maxHeight = (maxWidth / aspectRatio).round();
          }

          final inputAspectRatio = maxWidth / maxHeight;
          if (aspectRatio > inputAspectRatio) {
            maxHeight = (maxWidth / aspectRatio).round();
          } else {
            maxWidth = (maxHeight * aspectRatio).round();
          }

          canvas
            ..width = maxWidth
            ..height = maxHeight;
          ctx.drawImageScaled(video, 0, 0, maxWidth.toDouble(), maxHeight.toDouble());
        }

        try {
          final BlobCallback blobCallback = (Blob blob) {
            completer.complete(blob);
          }.toJS;

          canvas.toBlob(
            blobCallback,
            _imageFormatToCanvasFormat(imageFormat),
            (quality / 100).toJS,
          );
        } catch (e, s) {
          completer.completeError(
            PlatformException(
              code: 'CANVAS_EXPORT_ERROR',
              details: e,
              stacktrace: s.toString(),
            ),
            s,
          );
        }

        video.remove();
      }
    });

    video.onError.listen((Event e) {
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      video.remove();
      if (!completer.isCompleted) {
        final error = video.error!;
        completer.completeError(
          PlatformException(
            code: _kErrorValueToErrorName[error.code]!,
            message: error.message != '' ? error.message : _kDefaultErrorMessage,
            details: _kErrorValueToErrorDescription[error.code],
          ),
        );
      }
    });
    return completer.future;
  }

  String _imageFormatToCanvasFormat(ImageFormat imageFormat) {
    switch (imageFormat) {
      case ImageFormat.JPEG:
        return 'image/jpeg';
      case ImageFormat.PNG:
        return 'image/png';
      case ImageFormat.WEBP:
        return 'image/webp';
    }
  }
}
