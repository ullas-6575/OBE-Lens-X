import 'dart:io';
import 'package:http/io_client.dart';

IOClient createOcrClient() =>
    IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 15));
