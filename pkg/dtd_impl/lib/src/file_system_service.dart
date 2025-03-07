// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:dtd_impl/src/constants.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:dtd/dtd.dart';

import 'dtd_client.dart';

class FileSystemService {
  FileSystemService({required this.secret, required this.unrestrictedMode});

  final String secret;
  final bool unrestrictedMode;
  final List<Uri> _ideWorkspaceRoots = [];

  static const String _serviceName = 'FileSystem';

  void register(DTDClient client) {
    client
      ..registerServiceMethod(
        _serviceName,
        'readFileAsString',
        _readFileAsString,
      )
      ..registerServiceMethod(
        _serviceName,
        'writeFileAsString',
        _writeFileAsString,
      )
      ..registerServiceMethod(
        _serviceName,
        'listDirectoryContents',
        _listDirectoryContents,
      )
      ..registerServiceMethod(
        _serviceName,
        'setIDEWorkspaceRoots',
        _setIDEWorkspaceRoots,
      )
      ..registerServiceMethod(
        _serviceName,
        'getIDEWorkspaceRoots',
        _getIDEWorkspaceRoots,
      );
  }

  void _ensureIDEWorkspaceRootsContainUri(Uri uri) {
    // If in unrestricted mode, no need to do these checks.
    if (unrestrictedMode) return;

    for (final root in _ideWorkspaceRoots) {
      if (uri.path.startsWith(root.path)) {
        return;
      }
    }
    throw RpcErrorCodes.buildRpcException(
      RpcErrorCodes.kPermissionDenied,
    );
  }

  Map<String, Object?> _setIDEWorkspaceRoots(Parameters parameters) {
    final incomingSecret = parameters['secret'].asString;

    if (!unrestrictedMode && secret != incomingSecret) {
      throw RpcErrorCodes.buildRpcException(
        RpcErrorCodes.kPermissionDenied,
      );
    }
    final newRoots = <Uri>[];
    for (final root in parameters['roots'].asList.cast<String>()) {
      final rootUri = Uri.parse(root);
      if (rootUri.scheme != 'file') {
        throw RpcErrorCodes.buildRpcException(
          RpcErrorCodes.kExpectsUriParamWithFileScheme,
        );
      }

      newRoots.add(rootUri);
    }

    _ideWorkspaceRoots.clear();
    _ideWorkspaceRoots.addAll(newRoots);

    return RPCResponses.success;
  }

  Map<String, Object?> _getIDEWorkspaceRoots(Parameters _) {
    return IDEWorkspaceRoots(ideWorkspaceRoots: _ideWorkspaceRoots).toJson();
  }

  Future<Map<String, Object?>> _readFileAsString(Parameters parameters) async {
    final uri = _extractUri(parameters);
    _ensureIDEWorkspaceRootsContainUri(uri);
    final file = File.fromUri(uri);

    if (!(await file.exists())) {
      throw RpcErrorCodes.buildRpcException(
        RpcErrorCodes.kFileDoesNotExist,
      );
    }

    final content = await file.readAsString();

    return FileContent(content: content).toJson();
  }

  Uri _extractUri(Parameters parameters) {
    final uriString = parameters['uri'].asString;
    final uri = Uri.parse(uriString);
    if (uri.scheme != 'file') {
      throw RpcErrorCodes.buildRpcException(
        RpcErrorCodes.kExpectsUriParamWithFileScheme,
      );
    }
    return uri;
  }

  Future<Map<String, Object?>> _writeFileAsString(Parameters parameters) async {
    final uri = _extractUri(parameters);
    final contents = parameters['contents'].asString;
    final encoding = Encoding.getByName(
      parameters['encoding'].asString,
    )!;

    _ensureIDEWorkspaceRootsContainUri(uri);
    final file = File.fromUri(uri);
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    await file.writeAsString(
      contents,
      encoding: encoding,
    );

    return RPCResponses.success;
  }

  Future<Map<String, Object?>> _listDirectoryContents(
    Parameters parameters,
  ) async {
    final uri = _extractUri(parameters);
    _ensureIDEWorkspaceRootsContainUri(uri);
    final dir = Directory.fromUri(uri);
    if (!(await dir.exists())) {
      throw RpcErrorCodes.buildRpcException(
        RpcErrorCodes.kDirectoryDoesNotExist,
        data: {'directory': dir.uri.toFilePath()},
      );
    }

    final response = await (dir.list()).toList();

    final uris = response.map((e) => e.uri).toList();

    return UriList(uris: uris).toJson();
  }
}
