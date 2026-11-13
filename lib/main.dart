import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  runApp(const PrintServerApp());
}

class PrintServerApp extends StatelessWidget {
  const PrintServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Booth Server',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ServerScreen(),
    );
  }
}

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  String _serverStatus = "Starting server...";
  String _ipAddress = "Loading...";
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  void _log(String message) {
    setState(() {
      _logs.insert(0, "${DateTime.now().toLocal().toString().split('.')[0]} - $message");
    });
  }

  Future<void> _startServer() async {
    try {
      // Get the local Wi-Fi IP address of this laptop
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ip = interfaces.first.addresses.first.address;
      setState(() => _ipAddress = ip);

      // Start the server on port 5000
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 5000);
      setState(() => _serverStatus = "Server Running (Listening for iPad)");
      _log("Server bound to $ip:5000");

      await for (HttpRequest request in server) {
        // Handle CORS (Crucial for Flutter Web on iPad)
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          continue;
        }

        if (request.uri.path == '/print' && request.method == 'POST') {
          _log("Receiving photo from iPad...");
          try {
            // Read the JSON body sent from the iPad
            String content = await utf8.decoder.bind(request).join();
            var jsonData = jsonDecode(content);
            
            // Convert Base64 back to image bytes
            Uint8List imageBytes = base64Decode(jsonData['image']);
            
            // Print it!
            await _printImage(imageBytes);
            
            request.response.statusCode = HttpStatus.ok;
            request.response.write('{"status": "Printed Successfully"}');
            _log("Print job sent to VOZY G80!");
          } catch (e) {
            _log("Error: $e");
            request.response.statusCode = HttpStatus.internalServerError;
          }
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      }
    } catch (e) {
      setState(() => _serverStatus = "Server Error: $e");
    }
  }

  Future<void> _printImage(Uint8List imageBytes) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(imageBytes);

    // The 'printing' package has a built-in format for 80mm thermal paper!
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          );
        },
      ),
    );

    // This sends it directly to your default Windows printer (Make sure Vozy G80 is default!)
    await Printing.directPrintPdf(
      printer: const Printer(url: 'default'), // Or explicitly type your printer name
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kiosk Print Server')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Status: $_serverStatus", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("iPad URL Target: http://$_ipAddress:5000/print", style: const TextStyle(fontSize: 18, color: Colors.blue)),
            const Divider(height: 40, thickness: 2),
            const Text("Server Logs:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) => Text(_logs[index]),
              ),
            )
          ],
        ),
      ),
    );
  }
}