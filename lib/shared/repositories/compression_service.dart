import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

typedef ImageDecodingFunction = Future<Image?> Function(String);
typedef CompressorFunction = Future<File> Function(File);

class CompressionService {
  static final CompressionService instance = CompressionService();

  CompressorFunction? _getCompressorFuncByType(String fileType) {
    return {
      "image": compressImage,
    }[fileType];
  }

  ImageDecodingFunction? _getImgDecodingFuncByExt(String extension) {
    return {
      "jpg": decodeJpgFile,
      "jpeg": decodeJpgFile,
      "png": decodePngFile,
      "gif": decodeGifFile,
      "tiff": decodeTiffFile,
      "bmp": decodeBmpFile,
    }[extension];
  }

  static Future<List<File>> compressFiles(List<File> files) async {
    return await Future.wait(
      files.map((file) {
        return instance
                ._getCompressorFuncByType(
                  lookupMimeType(file.path)?.split("/").first ?? "",
                )
                ?.call(file) ??
            Future.value(file);
      }),
    );
  }

  static Future<File> compressImage(File file) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final decodingFunc = instance._getImgDecodingFuncByExt(ext);
      if (decodingFunc == null) return file;
      return await compute(_compressImageInBackground,
          [file, decodingFunc, RootIsolateToken.instance!]);
    } catch (e) {
      debugPrint("Compression failed: $e, using original file");
      return file;
    }
  }
}

Future<File> _compressImageInBackground(List<dynamic> data) async {
  try {
    final file = data[0] as File;
    final decodingFunc = data[1] as ImageDecodingFunction;
    final rootIsolateToken = data[2] as RootIsolateToken;

    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    var image = await decodingFunc(file.path);
    if (image == null) return file;

    final aspectRatio = image.width / image.height;
    double width, height;

    if (image.height > image.width) {
      height = min(1280, image.height * 1.0);
      width = aspectRatio * height;
    } else {
      width = min(1280, image.width * 1.0);
      height = width / aspectRatio;
    }

    image = copyResize(
      image,
      width: width.round(),
      height: height.round(),
      interpolation: Interpolation.linear,
    );

    final fileName = file.path.replaceAll(r'\', '/').split("/").last;
    final tempDir = await getTemporaryDirectory();
    final newPath = '${tempDir.path}/compressed_$fileName';
    final didConvert = await encodeJpgFile(
      newPath,
      image,
      quality: 50,
    );

    if (!didConvert) {
      return file;
    }

    return File(newPath);
  } catch (e) {
    debugPrint("Background compression error: $e");
    return data[0] as File;
  }
}

